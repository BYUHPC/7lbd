<img align="right" src="https://github.com/user-attachments/assets/343c6666-e3a0-4ce4-94ab-fc391e4f1b1f" width="250">

**7lbd** ("Seven Layer Bean Dip") allows users to launch and access a Microsoft Windows Desktop via [Open OnDemand](https://openondemand.org/) without requiring any additional Windows infrastructure. It treats Microsoft Windows as "just another Open OnDemand application," similar to JupyterLab, MATLAB, or VSCode, and provides users with access to their files in a secure and isolated environment.

## Features
- Run Windows 11 VMs on cluster nodes and make interactive sessions available through Open OnDemand.
- Utilizes [[3 different methods to deliver a desktop|Architecture#the-three-connectors]]; web-based RDP for speed and convenience, web-based VNC console access intended for systems administrators, and direct RDP access through standard RDP clients via a [[custom TLS proxy| OOD Proxy]] for maximum performance and utility.
- The Windows VM, desktop visualization processes, and the integrated samba server all run in a network namespace, limiting job network traffic to job processes only.  
- User files on the host node are available through an integrated samba server.
- Access into the network namespace is provided only for an incoming guacamole connection, or from an RDP client accessed through the [[ custom proxy|OOD Proxy]]. .

## Getting started
The [[getting started guide|Getting Started]] is a high-level summary about the install process to give you an idea of what to expect to get 7lbd running without having to read through the [[Installation Guide|Installation-Guide]].  The installation process has many steps, and this guide will give a 10,000 ft view of what to expect.

## License Information
[Include license text or link]

