================================================================================
  1. SYSTEM & HOST INFORMATION
================================================================================
Hostname         : hopper001.utep.edu
Date & Time      : Fri Jul 31 03:11:59 AM MDT 2026
Uptime           : up 11 weeks, 3 days, 16 hours, 35 minutes
Kernel Version   : 5.14.0-427.124.1.el9_4.x86_64
Operating System : Red Hat Enterprise Linux 9.4 (Plow)
Architecture     : x86_64

================================================================================
  2. SLURM JOB METADATA
================================================================================
SLURM Job ID     : 20263
SLURM Job Name   : bash
Partition        : dgx
Allocated Nodes  : hopper001
CPUs on Node     : 56
Allocated GPUs   : N/A
Mem Per Node/CPU : 131072

================================================================================
  3. CPU SPECIFICATIONS
================================================================================
--- Summary (lscpu) ---
Architecture:                         x86_64
CPU(s):                               224
On-line CPU(s) list:                  0-223
Model name:                           Intel(R) Xeon(R) Platinum 8480C
Thread(s) per core:                   2
Core(s) per socket:                   56
Socket(s):                            2
CPU(s) scaling MHz:                   59%
CPU max MHz:                          3800.0000
L3 cache:                             210 MiB (2 instances)
NUMA node(s):                         2
NUMA node0 CPU(s):                    0-55,112-167
NUMA node1 CPU(s):                    56-111,168-223

================================================================================
  4. RAM & SWAP SPECIFICATIONS
================================================================================
--- Memory Overview (free -h) ---
               total        used        free      shared  buff/cache   available
Mem:           2.0Ti        38Gi       355Gi       351Mi       1.6Ti       1.9Ti
Swap:             0B          0B          0B

--- Exact Memory Metrics (/proc/meminfo) ---
MemTotal:            2063425.92 MB
MemFree:              364074.08 MB
MemAvailable:        2024504.55 MB
SwapTotal:                 0.00 MB
SwapFree:                  0.00 MB

--- Online Memory Blocks (lsmem) ---
Memory block size:         2G
Total online memory:       2T
Total offline memory:      0B

================================================================================
  5. GPU SPECIFICATIONS
================================================================================
--- NVIDIA GPU Acceleration Detected ---
index, name, driver_version, pstate, pcie.link.gen.current, temperature.gpu, utilization.gpu [%], utilization.memory [%], memory.total [MiB], memory.free [MiB], memory.used [MiB]
0, NVIDIA H100 80GB HBM3, 595.71.05, P0, 5, 29, 0 %, 0 %, 81559 MiB, 81081 MiB, 0 MiB

--- GPU Details & CUDA Driver ---
Fri Jul 31 03:11:59 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 595.71.05              Driver Version: 595.71.05      CUDA Version: 13.2     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA H100 80GB HBM3          Off |   00000000:1B:00.0 Off |                    0 |
| N/A   29C    P0             71W /  700W |       0MiB /  81559MiB |      0%      Default |
|                                         |                        |             Disabled |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |

================================================================================
  6. DISK STORAGE & MOUNT POINTS
================================================================================
--- File System Utilization (df -h) ---
Filesystem                    Size  Used Avail Use% Mounted on
/dev/md127                    1.8T   65G  1.7T   4% /
/dev/md125                    489M  7.1M  482M   2% /boot/efi
/dev/md126                     28T  8.1T   19T  31% /scratch
129.108.156.40:/o_home         15T  369G   15T   3% /o_home
129.108.156.40:/opt/ohpc/pub  196G  144G   53G  74% /opt/ohpc/pub
129.108.156.40:/sched         196G  144G   53G  74% /sched
129.108.156.40:/opt/intel     196G  144G   53G  74% /opt/intel
rad:/home                     101T   34T   67T  34% /home
rad:/work                      41T  3.3T   37T   9% /work
rad:/project                  201T  164T   37T  82% /project


module avail

-------------------------------------------------------------- /opt/ohpc/pub/modulefiles ---------------------------------------------------------------
   EasyBuild/5.1.2      docker/27.3.1/rootless-docker    intel/2023.1.0        (D)    intel/2025.0.4      os
   R/4.5.1              g16/21.7                         intel/2023.2.1               intel/2025.1.1      papi/6.0.0
   autotools            gnu12/12.2.0                     intel/2024.0.0               intel/2025.3.3      pmix/4.2.9
   charliecloud/0.40    hwloc/2.12.0                     intel/2024.2.1.rpmnew        intel/2026.0.0      prun/2.2
   cmake/4.1.2          intel/2023.1.0.rpmnew            intel/2024.2.1               libfabric/1.18.0    ucx/1.18.0

  Where:
   D:  Default Module

If the avail list is too long consider trying:

"module --default avail" or "ml -d av" to just list the default modules.
"module overview" or "ml ov" to display the number of modules for each name.

Use "module spider" to find all possible modules and extensions.
Use "module keyword key1 key2 ..." to search for all possible modules matching any of the "keys".
