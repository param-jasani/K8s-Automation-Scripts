### The following outlines the workflow that was carried out to setup k8s cluster for training a model required for the project.

>[!chip] Node Specifications
> - `Processor` - i5 12<sup>th</sup> Gen (12500)
> - `RAM` - 8 GB
> - `GPU` - T400  (4 GB VRAM)
> - `OS` - Ubuntu 22.04.5 Server AMD64
> - `Total Number of Nodes` - 19

### Initial Setup
 - The project was kicked off by installing `ubuntu-22.04.5-live-server-amd64` on 18 nodes.
 - Following is the specification decided for partitioning the storage volume of `1TB HDD`  

>[!layers] Partition Table
> - `/` - 50 GB
> - `/home` - 50 GB
> - `swap` - 16 GB
> - `/data` - 512 GB
> - `/var` - 34 GB

- Later the filesystem(fs) of `/data` partition is formatted and the partition is wiped for setting up ceph fs.
- Our first week mainly delt with the installing the OS on each node, we first made a k8s cluster with a single control plane node, and 18 worker nodes, just to get a hang of it (as it was new for us).
- The first iteration was not stable at all as you might have already guessed, the load on control plane was too much and we had to load balance that.
- Also, we tried setting up ceph fs in first iteration but we were not able to do that (because of course vibe codderrss) so we moved onto longhorn (the easier one).
- We extracted over `1 TB` of shared storage, using longhorn, but longhorn doesn't give you that kind of performance that is required for training for transformers. The partition table config was different at that time, the one given here is the latest one, which we used to extract over `7.5 TB` of shared fs using ceph fs (yes we did that finally, find it in the later part of the story to know how we did that).
- Now the second iteration started of by formatting all nodes again (only the ubuntu server partition), we again installed the server image on all nodes. PS: we did that multiple times.
- The partition table given here is final as it provided us with efficiency, automation and a large storage that we wanted for storing the data that was required for training the model.
- Provided that we did the process multiple times, we learned a few things - 
	- Turn the swap off, if `kubelet.service` is not able to start, check `/etc/fstab`, you might have missed that file, and the swap turned on again after reboot, so comment the line of this particular partition.
	- We are currently not using longhorn, but the problem that we had met with was, longhorn by default uses the `/var/lib` partition as the default directory to store data in shared fs, therefore if the `/var` partition is small the resulting fs created in turn will be smaller one, that's why the first fs that we created was of `1 TB` only.
	- Also at that time we didn't knew that the services like `etcd` and `kube-apiserver` are not configured as system services in ubuntu, they are deployed as pods on the cluster so you can't directly interact with them using `systemctl`, this doesn't apply if you are setting up a manual or a standalone `etcd` for your k8s cluster.
	- And many more issues, at the time of writing I am not able to remember so that's why moving on like this.
- The next setup was robust, as it included setting up `1 HAProxy load balancer`, `3 control-plane nodes` and `15 worker nodes`.
- This setup provided us scalability, reliability and efficiency.
- Here is the network configuration for the nodes - [[Node IPs]].
