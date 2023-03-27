import os
import glob

currentdirpath = os.getcwd()
parentdirname = currentdirpath.split('/')[-2]
inputfilelist = glob.glob("../*")
for inputfile in inputfilelist:
   inputfilebasename = os.path.basename(inputfile)
   cmd = "gdal_translate -of GTIFF -ot BYTE -scale 0 65535 0 255 -b 1 -b 2 -b 3 " + inputfile + " " + currentdirpath + "/" + inputfilebasename
   os.system(cmd)
   print(inputfile + " translated.")
cmd = "gdalbuildvrt " + parentdirname + ".vrt" + " " + currentdirpath + "/*.tif"
os.system(cmd)
print("Mosaic VRT created.")
cmd = "gdal_translate -of GTIFF -ot BYTE -a_nodata 0 " + parentdirname + ".vrt" + " " + parentdirname + ".tif"
os.system(cmd)
print("Mosaic TIF created.")
