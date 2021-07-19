# Reproducer for CVE-2021-22555 as a container

First, this rolls in the exploit code from here as a handy pre-built container:
https://github.com/google/security-research/tree/master/pocs/linux/cve-2021-22555

Pre-built container: `quay.io/cgwalters/cve-2021-22555`

# Mitigation: seccomp profiles

A strong mitigation is to enable seccomp that denies `clone(CLONE_NEWUSER)`.  The [upstream Kubernetes docs](https://kubernetes.io/docs/tutorials/clusters/seccomp/) 
have some information on this - but leave deploying the policy on the node to the user.  In OpenShift 4, we have the [machine-config-operator](https://github.com/openshift/machine-config-operator/)
which can handle this.

Seccomp isn't really discussed in the [official docs](https://docs.openshift.com/container-platform/4.7/welcome/index.html).  However, the [security guide](https://www.redhat.com/rhdc/managed-files/cl-openshift-securty-guide-ebook-us287757-202103.pdf) does at least mention some of this, as does [this blog](https://www.openshift.com/blog/seccomp-for-fun-and-profit).

## Note: crio/podman runtime/default policy vs docker

`cri-o` in 4.7 ships with a default seccomp policy, but it is **not enabled by default**. 
`podman` and `docker` both also ship with a policy, and it *is* enabled by default (but they differ, see below).


The `cri-o` policy *does not* deny `clone(CLONE_NEWUSER)` by default - and this is also true of the `podman` policy.  However, the [docker default policy](https://docs.docker.com/engine/security/seccomp/#significant-syscalls-blocked-by-the-default-profile) **does** deny `clone(CLONE_NEWUSER)`:

```
[root@cosa-devsh ~]# rpm -q podman moby-engine
podman-3.1.2-1.fc33.x86_64
moby-engine-19.03.13-1.ce.git4484c46.fc33.x86_64
[root@cosa-devsh ~]# podman run --rm -ti registry.fedoraproject.org/fedora:34 /bin/sh -c 'unshare -U --keep-caps true'
[root@cosa-devsh ~]# echo $?
0
[root@cosa-devsh ~]# docker run --rm -ti registry.fedoraproject.org/fedora:34 /bin/sh -c 'unshare -U --keep-caps true'
unshare: unshare failed: Operation not permitted
errchan: json: cannot unmarshal array into Go struct field systemdEventMessage.MESSAGE of type string
[root@cosa-devsh ~]# echo $?
1
[root@cosa-devsh ~]# 
```

Or in other words: **docker is not vulnerable to this by default, but podman and cri-o are**.  (TODO: check containerd)


## Find and deploy a stronger seccomp policy

The [openshift/seccomp-for-fun-and-profit](https://www.openshift.com/blog/seccomp-for-fun-and-profit) blog entry
discusses some of this, and links to a profile the author generated.  This policy does deny `clone(CLONE_NEWUSER)`.

For convenience, this repository contains a copy of that profile in [more-restricted.json](more-restricted.json), and [a Butane file](50-worker-more-restricted-seccomp.bu.yaml) that generates a `MachineConfig` object that will deploy that profile to workers.

Use [the example pod file](pod.yaml) which has:

```
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: more-restricted.json
```

We get:

```
$ oc logs pod/cve-2021-22555
[+] Linux Privilege Escalation by theflow@ - 2021

[+] STAGE 0: Initialization
[*] Setting up namespace sandbox...
[-] unshare(CLONE_NEWUSER): Operation not permitted
```

Which should make the exploit unreachable.

However, this requires pods to opt-in.  Still TODO: Explore whether a seccomp policy can be made mandatory via a SecurityContextConstraint, or if we need a mutating admission webhook.
