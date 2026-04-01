#!/bin/bash
#===============================================
# Description: DIY script
# File name: diy-script.sh
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#===============================================

# enable rk3568 model adc keys
cp -f $GITHUB_WORKSPACE/configfiles/adc-keys.txt adc-keys.txt
! grep -q 'adc-keys {' package/boot/uboot-rk35xx/src/arch/arm/dts/rk3568-easepi.dts && sed -i '/\"rockchip,rk3568\";/r adc-keys.txt' package/boot/uboot-rk35xx/src/arch/arm/dts/rk3568-easepi.dts

# update ubus git HEAD
cp -f $GITHUB_WORKSPACE/configfiles/ubus_Makefile package/system/ubus/Makefile

# 近期istoreos网站文件服务器不稳定，临时增加一个自定义下载网址
sed -i "s/push @mirrors, 'https:\/\/mirror2.openwrt.org\/sources';/&\\npush @mirrors, 'https:\/\/github.com\/xiaomeng9597\/files\/releases\/download\/iStoreosFile';/g" scripts/download.pl


# 修改内核配置文件
sed -i "/.*CONFIG_ROCKCHIP_RGA2.*/d" target/linux/rockchip/rk35xx/config-5.10
# sed -i "/# CONFIG_ROCKCHIP_RGA2 is not set/d" target/linux/rockchip/rk35xx/config-5.10
# sed -i "/CONFIG_ROCKCHIP_RGA2_DEBUGGER=y/d" target/linux/rockchip/rk35xx/config-5.10
# sed -i "/CONFIG_ROCKCHIP_RGA2_DEBUG_FS=y/d" target/linux/rockchip/rk35xx/config-5.10
# sed -i "/CONFIG_ROCKCHIP_RGA2_PROC_FS=y/d" target/linux/rockchip/rk35xx/config-5.10



# 修改uhttpd配置文件，启用nginx
# sed -i "/.*uhttpd.*/d" .config
# sed -i '/.*\/etc\/init.d.*/d' package/network/services/uhttpd/Makefile
# sed -i '/.*.\/files\/uhttpd.init.*/d' package/network/services/uhttpd/Makefile
sed -i "s/:80/:81/g" package/network/services/uhttpd/files/uhttpd.config
sed -i "s/:443/:4443/g" package/network/services/uhttpd/files/uhttpd.config
cp -a $GITHUB_WORKSPACE/configfiles/etc/* package/base-files/files/etc/
# ls package/base-files/files/etc/



# 轮询检查ubus服务是否崩溃，崩溃就重启ubus服务，只针对rk3566机型，如黑豹X2和荐片TV盒子。
cp -f $GITHUB_WORKSPACE/configfiles/httpubus package/base-files/files/etc/init.d/httpubus
cp -f $GITHUB_WORKSPACE/configfiles/ubus-examine.sh package/base-files/files/bin/ubus-examine.sh
chmod 755 package/base-files/files/etc/init.d/httpubus
chmod 755 package/base-files/files/bin/ubus-examine.sh



# 集成黑豹X2和荐片TV盒子WiFi驱动，默认不启用WiFi
cp -a $GITHUB_WORKSPACE/configfiles/packages/* package/firmware/
cp -f $GITHUB_WORKSPACE/configfiles/opwifi package/base-files/files/etc/init.d/opwifi
chmod 755 package/base-files/files/etc/init.d/opwifi
# sed -i "s/wireless.radio\${devidx}.disabled=1/wireless.radio\${devidx}.disabled=0/g" package/kernel/mac80211/files/lib/wifi/mac80211.sh



# 集成CPU性能跑分脚本
cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64 package/base-files/files/bin/coremark-arm64
cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64.sh package/base-files/files/bin/coremark.sh
chmod 755 package/base-files/files/bin/coremark-arm64
chmod 755 package/base-files/files/bin/coremark.sh


# iStoreOS-settings
git clone --depth=1 -b main https://github.com/xiaomeng9597/istoreos-settings package/default-settings


# 定时限速插件
git clone --depth=1 https://github.com/sirpdboy/luci-app-eqosplus package/luci-app-eqosplus


# 修复LuCI网络接口页面 CBIAbstractValue 报错（form.RichListValue不存在于22.03）
sed -i "s/form\.RichListValue/cbiRichListValue/g" feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/interfaces.js

# 复制dts设备树文件到指定目录下
cp -a $GITHUB_WORKSPACE/configfiles/dts/rk356x/* target/linux/rockchip/dts/rk3568/


# ==================== OrangePi 5 Plus 定制 ====================

# 1. 替换DTB：用Debian官方提取的DTB替换编译生成的DTB（解决无法启动问题）
# 将自定义DTB复制到构建根目录
cp -f $GITHUB_WORKSPACE/configfiles/rk3588-orangepi-5-plus.dtb custom-opi5plus.dtb

# 修改镜像Makefile：在boot-common中DTB复制后，追加一行覆盖OPi 5 Plus的DTB
python3 << 'PYEOF'
import sys
mf = 'target/linux/rockchip/image/Makefile'
with open(mf) as f:
    lines = f.readlines()
new_lines = []
target_line = '$(CP) $(KDIR)/image-$(firstword $(DEVICE_DTS)).dtb $@.boot/rockchip.dtb'
added = False
for line in lines:
    new_lines.append(line)
    if not added and target_line in line:
        indent = line[:len(line) - len(line.lstrip())]
        new_lines.append(indent + '[ "$(firstword $(DEVICE_DTS))" = "rk3588-orangepi-5-plus" ] && [ -f $(TOPDIR)/custom-opi5plus.dtb ] && $(CP) $(TOPDIR)/custom-opi5plus.dtb $@.boot/rockchip.dtb || true\n')
        added = True
with open(mf, 'w') as f:
    f.writelines(new_lines)
if added:
    print("OK: DTB override line added to Makefile")
else:
    print("WARNING: target line not found in Makefile", file=sys.stderr)
PYEOF

# 2. 网络配置：eth0=LAN(192.168.100.1), eth1=WAN(DHCP)
# 修改02_network：为OPi 5 Plus创建独立case条目（原始配置eth1=LAN,eth0=WAN需要互换）
python3 << 'PYEOF'
import re
nf = 'target/linux/rockchip/rk35xx/base-files/etc/board.d/02_network'
with open(nf) as f:
    content = f.read()

# Check if orangepi-5-plus is in a multi-board pattern (e.g. "board1|\nboard2)")
# or a standalone pattern
if 'xunlong,orangepi-5-plus|' in content:
    # Remove from grouped pattern and add separate entry before it
    content = content.replace('xunlong,orangepi-5-plus|\n', '')
    content = content.replace('xunlong,orangepi-5-plus|\r\n', '')
    # Find the case block and add OPi 5 Plus as separate entry before it
    insert = "xunlong,orangepi-5-plus)\n\tucidef_set_interfaces_lan_wan 'eth0' 'eth1'\n\t;;\n"
    # Insert before the first board pattern in the case statement
    content = content.replace("case \"$board\" in\n", "case \"$board\" in\n" + insert, 1)
elif 'xunlong,orangepi-5-plus)' in content:
    # Standalone entry - just swap the arguments
    content = re.sub(
        r"(xunlong,orangepi-5-plus\).*?\n\s*)ucidef_set_interfaces_lan_wan\s+'eth1'\s+'eth0'",
        r"\1ucidef_set_interfaces_lan_wan 'eth0' 'eth1'",
        content
    )

with open(nf, 'w') as f:
    f.write(content)
print("OK: 02_network updated for OPi 5 Plus (eth0=LAN, eth1=WAN)")
PYEOF

# 3. 确保uci-defaults脚本有执行权限（DHCP、opkg源等在99-custom-network中设置）
chmod 755 package/base-files/files/etc/uci-defaults/99-custom-network 2>/dev/null
