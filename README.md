# lagobello-drawings
Lago Bello Drawings and Web Map Products

Dependencies for running in Ubuntu:
sudo apt update
sudo apt install software-properties-common
sudo add-apt-repository universe
sudo apt update   # again after adding universe
sudo apt install install gdal-bin python3-gdal git-lfs


Troublehsooting:  
If you run into the following issue, it is because the repo was cloned without git-lfs. 
  FAILURE:
    Unable to open datasource `archive/vitto/LagoBello-PLANSC-VITTO-20250702.dxf' with the following drivers.
After having installed git-lfs try running the following in the repo.
git lfs pull
