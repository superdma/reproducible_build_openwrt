<kdb>#reproducible build shell script for openwrt</kdb>
***

*USAGE:*`bash reproducible_build.sh ar71xx`

simliar target: ar71xx/brcm47xx/kirkwood/lantiq/mediatek/omap/ramips/sunxi/tegra/x86, you can choose any one of these.
 
***  
1. First we need to make sure the dependencies are installed (for Debian/Ubuntu):
`
sudo apt install subversion g++ zlib1g-dev build-essential git python python3
  
sudo apt install libncurses5-dev gawk gettext unzip file libssl-dev wget
  
sudo apt install libelf-dev ecj fastjar java-propose-classpath
`
In addition for Debian 10:

`sudo apt install python3-distutils`

or for ubuntu 18.04 or later

`sudo apt install build-essential libncursesw5-dev python unzip`   
***

2. avoid warning when we set LC_ALL

`sudo apt-get install locales, locales-all`
***

3. install faketime for set env FAKETIME

`sudo apt-get install faketime`
  
`dpkg -L libfaketime`
  
modify `export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1` in script reproducible_build.sh
***

4. install compare tool diffoscope

`sudo apt-get install diffoscope`
***
