#!/bin/bash

#############################################################################################
# 
#  1. Only 8-bit GeoTIFFs are supported. [Run gdalinfo to find your GeoTIFF's resolution.]
#  2. Use of Web Mercator EPSG:3857 is recommended.
#  3. Set blocksize to 256x256.
#  4. If compression is needed, use LZW. [Install LibTIFF first.]
#  5. Remove Alpha band, if applicable.
#
#############################################################################################

mapbox_user=stout
mapbox_access_token=sk.eyJ1Ijoic3RvdXQiLCJhIjoiY2tyY291ZHZuNGlyaTJ2cXV5cHdsY3FhNSJ9.YlS_CHPoUtA4cnUpiQB3ZQ
tileset_bbox="[-122, 34, -118, 38]"

if [ $# -ne 1 ]
then
    echo "Usage: $0 inputfile"
    echo "Argument: The inputfile argument must be a GeoTIFF file with .tif|.tiff extension."
    echo "Example: $0 field.tif"
    exit 1
fi

# Declare variables
arg=`basename $1`
fbas=`echo ${arg%%.*}`
fext=`echo ${arg##*.}`
tileset_id="$fbas-tileset"

if [ $fext == tif ] || [ $fext == tiff ]
then
    #tiffcp -c lzw $1 datafile
    datafile=$1
else
    echo "[ERR] The extension of input file is not valid."
    exit 1
fi

# Retrieve AWS credentials for uploading the input file to a S3 bucket, which serves as the temporary staging area.
curl -X POST https://api.mapbox.com/uploads/v1/$mapbox_user/credentials?access_token=$mapbox_access_token \
    | jq -r '.accessKeyId, .secretAccessKey, .sessionToken, .url, .bucket, .key' > tempfile

# Stage the input file on AWS S3.
while read line 
do
    aws_params+=( $line )
done < tempfile
aws_access_key_id=${aws_params[0]}
aws_secret_access_key=${aws_params[1]}
aws_session_token=${aws_params[2]}
aws_s3_url=${aws_params[3]}
aws_s3_bucket=${aws_params[4]}
aws_s3_key=${aws_params[5]}
aws configure set aws_access_key_id $aws_access_key_id --profile mapbox
aws configure set aws_secret_access_key $aws_secret_access_key --profile mapbox
aws configure set aws_session_token $aws_session_token --profile mapbox
aws configure set region us-east-1 --profile mapbox

aws s3 cp $1 s3://$aws_s3_bucket/$aws_s3_key --profile mapbox
echo "[INF] The input file has been staged on AWS S3."

# Upload the input file staged on AWS S3 to Mapbox and then create raster tileset.
upload_json=`cat <<EOF
{ 
    "url": "http://$aws_s3_bucket.s3.amazonaws.com/$aws_s3_key",
    "tileset": "$mapbox_user.$tileset_id",
    "name": "$tileset_id"
}
EOF
`
curl -X POST https://api.mapbox.com/uploads/v1/$mapbox_user?access_token=$mapbox_access_token \
     -H "Content-Type: application/json" \
     -H "Cache-Control: no-cache" \
     -d "$upload_json" \
    | jq -r '.id' > tempfile 

upload_id=`cat tempfile`
if [[ -n $upload_id ]]
then
    echo "[INF] Uploading from AWS S3 to Mapbox in progress. Upload job id is $upload_id."
else
    echo "[ERR] Uploading from AWS S3 to Mapbox fails to proceed."
    exit 1
fi

# Watch for the completion of the upload.
completed=false
while [ $completed == false ]
do
    sleep 3
    curl -X GET https://api.mapbox.com/uploads/v1/$mapbox_user/$upload_id?access_token=$mapbox_access_token \
        | jq -r '.complete' > tempfile
    completed=`cat tempfile`
done
echo
echo "[INF] The input file has been uploaded, and the raster tileset named $mapbox_user.$tileset_id has been created."

rm tempfile
exit 0
