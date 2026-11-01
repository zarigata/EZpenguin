# First boot and headless setup

EZpenguin configures a flashed system on its first real OS boot. The interactive
wizard runs through systemd on tty1. Restarting a normal Docker container does
not boot systemd and is not a complete first-boot test.

## Interactive setup

1. Boot a compatible image or complete installation from the live ISO.
2. Set locale, timezone, keyboard layout, and hostname.
3. Create a regular user with a unique password.
4. Choose whether to enable SSH and update packages.
5. Complete the wizard and reboot when prompted.

The optional global-password setting also unlocks root console login using the
same password as your user. Root SSH login remains disabled. Leave this option
off if you do not need root password login.

## Headless setup

Mount the flashed root filesystem on another machine and put a firstboot.conf
file in its /boot directory before first boot.

~~~ini
EZ_LOCALE=en_US.UTF-8
EZ_TIMEZONE=America/Sao_Paulo
EZ_KEYMAP=us
EZ_HOSTNAME=homelab
EZ_USERNAME=penguin
EZ_PASSWORD=replace-with-a-unique-password
EZ_SSH_ENABLE=1
EZ_UPGRADE=1
EZ_REBOOT=1
~~~

The current parser accepts only letters, digits, and the characters _.:/+@- in
values. Protect the file: it includes a plaintext password. The retained
firstboot.conf.applied file may still contain that password; remove it after
successful configuration. Omitting the password creates a locked account.

## After setup

~~~bash
ez-info
ez-doctor
ez-net
sudo ez-config
~~~

Use ez-config for subsequent changes. The configured marker prevents repeating
initial setup automatically; re-running the wizard is not the usual settings
workflow.

See [Installation](../docs/INSTALLATION.md) for every install method and
[System tools](system-tools.md) for the commands included in EZpenguin.
