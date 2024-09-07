First install docker:

sudo apt install docker

Then do this:

sudo systemctl start docker
sudo docker pull ubuntu
sudo docker run -it ubuntu

Once your in the docker do:

mkdir ~/.config
mkdir ~/.config/nvim
mkdir ~/.config/nvim/lua

apt update
apt upgrade
apt install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip git luarocks libsqlite3-dev

git clone https://github.com/neovim/neovim.git

cd neovim

make CMAKE_BUILD_TYPE=RelWithDebInfo

make install

luarocks install lsqlite3  (if smth doesnt work also try apt install lua5.4)

put init.lua into ~/.config/nvim

put MagiSnipp.lua into ~/.config/nvim/lua

type nvim in the bash console and press enter, lazy together with some other plugins should be then auto-installed

Plugin description:

MagiSnipp is a nvim plugin that manages your snippets its basically
a clipboard manager, for example if you have a function that you oftenly
re-use you can select it in visual mode. For this be in normal mode go with your cursor
to the start line you want to select then hold the left mousebutton down and
drag till you selected your snippet that you want to save (the lines should be highlighted).
After you selected the lines, go back to normal mode with ESC and then press \ + g
(so just backslash and g) to save your snippet. You are then prompted
to give a keymap (recommended is for example <C-x> which is Ctrl + x (Ctrl and x) (so literally type <C-x>) or
you can also try mapping it to for or some other word. Then you also have to give your snippet a name
and a short description on what it does/is. To paste it go into insert mode and press the keymapping
you assigned the snippet to. To look at your currently saved snippets
press \ + o (\ and o) to open the mappings window, there you can see all your saved snippets. You can
move around with the up and down arrow keys. If you like to look at content of your saved snippet
press Enter, a new window opens and there is the content of your snippet. To go back press b and to quit
type :q and confirm with enter. If you are in the mappings window you can also press q to delete
a snippet.

NOTE: keymappins only work in insert mode
(if for some reason sqlite3 cant find db specify path in MagiSnipp.lua -> local path_db variable)
####################################################################################################
analysis.py

The analysis.py includes 4 functions that plot different visualizations of the NYC
Motor Vehilce Crash dataset.

Dependencies:

apt install python3
apt install python3-pip
pip install pandas
pip install matplotlib
pip install geopandas
pip install Pyarrow

Download the dataset:

wget https://data.cityofnewyork.us/api/views/h9gi-nx95/rows.csv?accessType=DOWNLOAD

rename it with (mv) to Motor_Vehicle_Collisions_-_Crashes.csv

if download doesnt work go to -> https://catalog.data.gov/dataset/motor-vehicle-collisions-crashes

also install a pdf viewer (apt install evince okular foxit-reader mupdf xpdf)

run with python3 analysis.py or VS Code (boroughs plot took for me 5min all other < 10s)

NOTE: in the docker I wasnt able to open any pdfs but it should work on normal ubuntu