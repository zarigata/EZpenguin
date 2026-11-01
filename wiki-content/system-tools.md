# EZpenguin system tools

These Bash tools are copied into the image from the rootfs overlay. Software
installed through the optional catalog is separate from these built-in commands.

## ez-info: system overview

~~~bash
ez-info
~~~

Displays OS identity, hardware and resource information, and first-boot state.
Review output for host identifiers before sharing a support report.

## ez-doctor: health check

~~~bash
ez-doctor
~~~

Checks common system conditions. A passing report is not a full security audit
or proof that an installed application is correctly configured.

## ez-net: network diagnostics

~~~bash
ez-net
~~~

Use it as a starting point for connectivity problems. Standard base commands
include ip, ping, curl, and the OpenSSH client.

## ez-config: change settings

~~~bash
sudo ez-config
~~~

The menu exposes settings such as hostname, timezone, locale, keymap, SSH, and
passwords. Network or SSH changes can interrupt remote access; keep a console
available when changing the path you use to connect.

## ez-software: catalog

~~~bash
ez-software list
ez-software search python
sudo ez-software install docker python
sudo ez-software
~~~

The tool reads the software catalog, asks APT to install the listed packages,
and runs each entry's post-install shell snippet. Post-install errors may be
reported without aborting, so inspect the output and verify the service rather
than assuming a successful package install means complete application setup.

The [software directory](../docs/index.html#software) and the wiki home include
a guide for every entry, including package names and the exact hook.

## ez-update: package updates

~~~bash
sudo ez-update
~~~

The current script runs apt-get update, apt-get upgrade -y, then
apt-get autoremove -y --purge. It does not create a snapshot, provide atomic
rollback, or rebuild the OS image. Review package changes and back up application
data before an important upgrade.

## ez-backup: configuration archives

~~~bash
sudo ez-backup create /root/ezpenguin-config.tar.gz
ez-backup list /root/ezpenguin-config.tar.gz
sudo ez-backup restore /root/ezpenguin-config.tar.gz
~~~

Backs up selected EZpenguin and system configuration paths, including network,
SSH, locale, hostname, and fstab files. It is not a full disk image and does not
back up application databases, home directories, or container volumes by default.

Restoring overwrites the archived paths after confirmation. Review the archive
and use only an archive you trust. Keep separate database and application-data
backups, ideally with a tested restore procedure.

## ez-install and ez-firstboot

ez-install is the disk installer used by the live environment. It can erase the
selected disk. ez-firstboot performs initial configuration. Start with the
[installation guide](../docs/INSTALLATION.md), rather than running either tool
blindly on a valuable host.
