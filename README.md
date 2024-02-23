# SCEPMan

SCEPman is a cloud-based certification authority. It is installed within minutes and requires virtually no operations efforts.

It easily enables your Intune and JAMF managed clients for certificate based WiFi authentication based on the SCEP protocol, but it can also issue certificates for Domain Controllers or TLS Servers.

Please see https://docs.scepman.com/ for a full documentation.

## VersionInformation.txt

This repository contains two files VersionInformation.txt in the directories /dist and /dist-certmaster. The file contains a version number. SCEPman and SCEPman Certificate Master, respectively, load the VersionInformation.txt regularly to see whether their version is current. If it isn't, they will display a message on the homepage and log a warning.

Therefore, VersionInformation.txt most of the time has the same version number as the binaries of the production channel in the ZIP next to it, but there is a delay after an update. There is [a more detailed explanation and a workaround](https://github.com/scepman/install/issues/#17#issuecomment-1864030630) if your release pipepline needs to know the version number of the latest release.