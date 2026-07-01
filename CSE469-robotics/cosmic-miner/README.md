# CosmicMiner

Robotics control and multi-agent exploration projects for CSE469: Introduction to Robotics, implemented on top of the CosmicMiner simulation framework.

https://github.com/hoonably/cse-archive/releases/download/assets-v1/cosmicminer.mp4

Project Page: https://jeonghoonpark.com/project/cosmicminer-robotics

## Overview

This repository contains three progressive projects focused on robot control logic, autonomous navigation, and multi-agent coordination. Unity is used as the simulation runtime; the main work is in control algorithms, sensor-driven navigation, and deployable robot mechanism design.

- **Project 1**: Rocket control with Arduino-based joystick input
- **Project 2**: Single drone navigation with GPS waypoints and checkpoints
- **Project 3**: Multi-agent drone exploration with autonomous path planning

## Focus Areas

- Control systems for thrust vectoring, braking, and joystick-based operation
- Sensor-driven navigation using IMU/GPS simulation, checkpoints, and braking distance logic
- Multi-agent exploration with dynamic path assignment, shared map state, and coordinated deployment
- Robot mechanism behavior for carrier control, servo actuation, and drone silo deployment

## Projects

### Project 1: Rocket Control System 🏆

Arduino joystick-controlled rocket simulator with thrust and brake management.

**🥇 1st Place Winner** - Best performance among all teams in the course.

**Core Implementation**: [`ControlUnit.cs`](src/project1/ControlUnit.cs)
- Analog joystick input processing (A0-A5 ADC values)
- Digital button handling (D2-D6)
- Engine on/off toggle with dead zone filtering
- Servo-based thrust vectoring control
- Brake system management

---

### Project 2: GPS-based Drone Navigation

Single drone autonomous navigation through GPS waypoints with checkpoint tracking.

**Core Implementation**: [`DroneControlUnit.cs`](src/project2/DroneControlUnit.cs)
- IMU and GPS sensor simulation
- CSV-based servo timeline control
- Checkpoint detection and logging
- Real-time velocity and position tracking
- Automated brake distance calculation

---

### Project 3: Multi-Agent Drone Coordination

Autonomous multi-drone exploration system with carrier deployment, coordinated navigation, and shared exploration state.

**Core Implementations**:
- [`ControlUnit.cs`](src/project3/ControlUnit.cs) - Rocket/carrier control with manual/auto modes
- [`DroneControlUnit.cs`](src/project3/DroneControlUnit.cs) - Multi-drone path planning and coordination
- [`ServoBehave.cs`](src/project3/ServoBehave.cs) - Servo actuation for drone deployment
- [`DroneSilo_behave.cs`](src/project3/DroneSilo_behave.cs) - Drone silo mechanism control

**Features**:
- Multi-drone deployment from carrier rocket
- Autonomous path planning and exploration
- Coordinated takeoff and landing sequences
- Dynamic checkpoint assignment
- Shared map and branch-state coordination
- Real-time multi-agent control

## Unity Setup

1. Create project
<img src="./img/unity-1.png" width="50%">

2. Project Settings: .NET Framework
<img src="./img/unity-2.png" width="50%">

3. Import .unitypackage file

## Directory Structure

```
├── src/
│   ├── project1/      # Rocket control system
│   ├── project2/      # GPS drone navigation
│   └── project3/      # Multi-agent coordination
├── Project1.unitypackage
├── Project2.unitypackage
└── Project3.unitypackage
```

## Acknowledgments

Built on the [CosmicMiner](https://github.com/nshbae/CosmicMiner) starter framework by nshbae. This repository documents my course work on robot control, autonomous exploration, and mechanism behavior on top of that base.

## License

This repository is a personal archive of a university robotics project.
The original starter code and this repository are licensed under the MIT License.
See the LICENSE file for details.
