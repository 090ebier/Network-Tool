
Network Management Tool

---

#### Introduction

The **Network Management Tool** is a script that helps system administrators manage and monitor network configurations and services on Linux systems through a user-friendly interface. It supports managing network configurations, firewalls (using `nftables`), Open vSwitch, and provides real-time network monitoring.

---

#### Features

- **Basic Linux Network Configuration**: Manage and configure basic network settings such as IP addresses, routes, and DNS.
- **Firewall Management (NFTables)**: Set up and manage firewalls using `nftables`.
- **Open vSwitch Management**: Manage Open vSwitch (OVS) bridges, ports, and settings.
- **Network Monitoring**: Monitor real-time network statistics and activity.
- **Script Install/Update**: Easily install or update the script.

---

#### Prerequisites

Before you install and use the **Network Management Tool**, ensure that the following packages are installed on your system:

- **Git**: To clone the repository.
- **Dialog**: To create the user interface.
- **NFTables**: For firewall management.
- **nload**, **sysstat**, **net-tools**, **openvswitch-switch**, **tcpdump**, **dnsutils**, **iproute2**, **ifstat**: For various network management and monitoring functions.
- **Python 3**: To run the necessary Python scripts.
- **Pip3**: To install the required Python packages like `matplotlib`, `weasyprint`, and `requests`.

---

#### Installation

To install the **Network Management Tool**, follow the steps below:

If git and curl are not already installed, install them with the following command:

   ```bash
   apt-get update
   apt-get install git curl -y
   ```

1. **Run the Installer:**

   You can use the following command to clone and install the tool directly:

   ```bash
   curl -Ls https://raw.githubusercontent.com/090ebier/Network-Tool/main/install.sh -o /tmp/install.sh
   sudo bash /tmp/install.sh
   ```

   Alternatively, you can download and run the installer manually:

   ```bash
   git clone https://github.com/090ebier/Network-Tool.git /opt/net-tool
   sudo bash /opt/net-tool/install.sh
   ```

2. **Post-Installation**:

   Once installed, you can run the tool by typing:

   ```bash
   net-tool
   ```

   Ensure that the `/usr/local/bin/net-tool` symlink is created, allowing you to run the tool from any terminal.

---

#### Usage

After installation, the tool will start by displaying a welcome message, followed by a main menu. The menu provides options to access different modules:

1. **Basic Linux Network Configuration**: Manage your network interfaces and settings.
2. **Firewall Management (NFTables)**: Configure and manage firewall rules.
3. **Open vSwitch Management**: Manage Open vSwitch (OVS) configurations.
4. **Network Monitoring**: Monitor real-time network traffic and statistics.
5. **Install/Update Script**: Update the tool to the latest version or reinstall if needed.
6. **Exit**: Quit the tool.

Simply select the desired option, and the corresponding module or task will be executed.

---

#### Updating the Tool

To update the **Network Management Tool** to the latest version, you can select the "Install or Update Script" option from the main menu (Option 5). This will automatically download and apply the latest updates from the GitHub repository.

Alternatively, you can manually run the update command:

```bash
curl -Ls https://raw.githubusercontent.com/090ebier/Network-Tool/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

#### Uninstallation

To uninstall the **Network Management Tool**, you can manually remove the installation directory and symbolic link:

```bash
sudo rm -rf /opt/net-tool
sudo rm /usr/local/bin/net-tool
```

---

#### Troubleshooting

If you encounter any issues such as permission errors or missing dependencies, ensure the following:

- **Permissions**: Ensure that the necessary scripts are executable. You can manually set the permissions:
  
  ```bash
  sudo chmod +x /opt/net-tool/*.sh
  sudo chmod +x /opt/net-tool/Module/*.sh
  ```

- **Dependencies**: Make sure all required packages are installed. You can rerun the installer script to install missing dependencies.

- **Logs**: Check the terminal output for any error messages. If a specific module fails to run, ensure that the required services (like Open vSwitch) are running on your system.

---

#### Contribution

Feel free to fork the repository, create new features, or report issues through GitHub. We welcome contributions from the community to improve the **Network Management Tool**.

---

#### License

This project is licensed under the MIT License. For more details, see the `LICENSE` file in the repository.

---

#### Contact

For any further questions or support, please contact the project maintainer via GitHub at: [https://github.com/090ebier](https://github.com/090ebier).

---

Enjoy managing your network with the **Network Management Tool**!
