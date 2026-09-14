# AGX Thor / t264 (JetPack 7): select NVIDIA's stock redundant (A/B) external
# NVMe layout instead of the single-rootfs default (flash_l4t_t264_nvme.xml).
# Both ship in the L4T BSP, so this only names the one we want; the data
# partition is appended to it by the tegra-storage-layout-base bbappend, which
# does the same to every other machine's layout.
PARTITION_LAYOUT_EXTERNAL:tegra264 = "flash_l4t_t264_nvme_rootfs_ab.xml"
