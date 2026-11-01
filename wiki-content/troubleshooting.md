# Troubleshooting

Start with the smallest reproducible problem. Record the EZpenguin version,
architecture, boot method, machine model, and exact error. Do not include
passwords, API keys, private SSH keys, or unreviewed packet captures.

## A package will not install

~~~bash
sudo apt-get update
apt-cache policy PACKAGE_NAME
sudo dpkg --audit
sudo apt-get check
~~~

Replace PACKAGE_NAME with a package listed on the software guide. A missing
candidate means the current repositories cannot supply that package. Catalog
presence alone is not a guarantee of availability on every architecture.

The legacy gitea-light recipe requests Gogs. The gitdaemon recipe installs git
and daemon but does not configure a Git hosting service. These limitations are
called out in their individual wiki guides.

## A service did not start

~~~bash
systemctl --failed --no-pager
systemctl status SERVICE_NAME --no-pager
sudo journalctl -u SERVICE_NAME -n 60 --no-pager
sudo ss -lntup
~~~

Replace SERVICE_NAME with the actual service from the recipe. Check for missing
configuration, another listener on the same port, or insufficient permissions.
Package installation and a post-install hook are not a complete deployment.

## The software menu behaves unexpectedly

Use the non-interactive commands while diagnosing a menu problem:

~~~bash
ez-software list
ez-software search docker
sudo ez-software install docker
~~~

The web directory documents recipes, but it does not run installation on your
machine. Copy a command only after reading the corresponding guide.

## A command's manual page is missing

The minimal image excludes man-db and standard manpage packages. Use the
program's --help output when available, the on-site software reference, or the
[Debian manual pages](https://manpages.debian.org/bookworm/). You can install local
manual-page packages through APT if you prefer; they increase disk usage.

## SSH cannot connect

Check the machine IP address, the SSH option selected at first boot, firewall
rules, and whether the SSH service is running. Root SSH login is disabled;
connect as the regular user created by the wizard. A container without systemd
will not start the image's normal boot services automatically.

## The image will not boot

Use the amd64 image on x86-64 hardware and the ARM64 image on compatible UEFI
ARM64 systems. Universal board support and Secure Boot compatibility are not
promised. Confirm your flash completed, check firmware boot mode, and try a VM
to separate image behavior from a hardware-specific issue.

## A desktop changed the default boot

XFCE and LXDE recipes set graphical.target. To return to terminal boot:

~~~bash
sudo systemctl set-default multi-user.target
~~~

Reboot when ready. This changes the default target; it does not uninstall the
desktop packages.

## Where to ask for help

Read the relevant wiki guide first. For a project defect, use the site's
explicit Report an issue link with a minimal reproduction and sanitized logs.
Documentation remains here on the website; source collaboration happens in the
repository.
