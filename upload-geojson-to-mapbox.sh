#!/bin/bash

mapbox_user=stout
mapbox_access_token=sk.eyJ1Ijoic3RvdXQiLCJhIjoiY2tyY291ZHZuNGlyaTJ2cXV5cHdsY3FhNSJ9.YlS_CHPoUtA4cnUpiQB3ZQ
tileset_bbox="[-122, 34, -118, 38]"

if [ $# -ne 1 ]
then
    echo "Usage: $0 inputfile"
    echo "Argument: The inputfile argument must be either a GeoJSON file with .json|.geojson extension or a Line-Delimited GeoJSON file with .ldgeojson|.ldgeojson.txt extension."
    echo "Example: $0 plants.json"
    exit 1
fi

# Declare variables
arg=`basename $1`
fbas=`echo ${arg%%.*}`
fext=`echo ${arg##*.}`
tileset_source_id="$fbas-source"
tileset_layer_id="$fbas-layer"
tileset_id="$fbas-tileset"
tileset_style_id="$fbas-style"

# Convert GeoJSON to LDGeoJSON if the input file is in GeoJSON format (i.e., if not in LDGeoJSON format).
if [ $fext == json ] || [ $fext == geojson ]
then
    (jq -c '.features[]' < $1) > datafile
    if [ ! -s datafile ]
    then 
        echo "[ERR] The input file is not in valid GeoJSON format."
        exit 1
    fi
elif [ $fext == ldgeojson ] || [ $fext == txt ]
then
    datafile=$1
else
    echo "[ERR] The extension of input file is not valid."
    exit 1
fi

# Create vector tileset source 
curl -X PUT https://api.mapbox.com/tilesets/v1/sources/$mapbox_user/$tileset_source_id/?access_token=$mapbox_access_token \
     -H "Content-Type: multipart/form-data" \
     -F file=@datafile \
    | jq -r '.id' > tempfile

id_in_response=`cat tempfile`
if [ $id_in_response == "mapbox://tileset-source/$mapbox_user/$tileset_source_id" ]
then
    tileset_source_url=$id_in_response
    echo "[INF] Tileset source $tileset_source_id has been created at $tileset_source_url."
    completed=true
else
    echo "[ERR] Tileset source cannot be created because the input file is not in valid format."
    exit 1
fi

# Define and validate tileset recipe
tileset_recipe_json=`cat <<EOF
{ 
    "recipe": {
        "version": 1,
        "layers": { 
            "$tileset_layer_id": { 
                "source": "$tileset_source_url",
                "minzoom": 4,
                "maxzoom": 22,
                "features": {
                },
                "tiles": {
                    "bbox": $tileset_bbox,
                    "layer_size": 2500
                }
            }
        }
    },
    "name": "$tileset_id"
}
EOF
`
tileset_recipe_json_proper=`echo $tileset_recipe_json | jq -r '.recipe'`

curl -X PUT https://api.mapbox.com/tilesets/v1/validateRecipe?access_token=$mapbox_access_token \
     -H "Content-Type: application/json" \
     -d "$tileset_recipe_json_proper" \
    | jq -r '.valid' > tempfile
recipe_valid=`cat tempfile`
if [ $recipe_valid == true ]
then 
    echo "[INF] Tileset recipe validated."
else 
    echo "[ERR] Tileset recipe not valid"
    exit 1
fi
#rm tempfile

# Define functions to create a tileset and publish the tileset.
create_tileset() {
    curl -X POST https://api.mapbox.com/tilesets/v1/$mapbox_user.$tileset_id?access_token=$mapbox_access_token \
         -H "Content-Type: application/json" \
         -d "$tileset_recipe_json" \
        | jq -r '.message' > tempfile
    tileset_creation_message=`cat tempfile`
    echo "[INF] $tileset_creation_message"
}

publish_tileset() {
    curl -X POST https://api.mapbox.com/tilesets/v1/$mapbox_user.$tileset_id/publish?access_token=$mapbox_access_token \
        | jq -r '.jobId' > tempfile
    tileset_job=`cat tempfile`
    if [ $tileset_job != "" ]
    then
        echo "[INF] A job to publish the tileset has been created with job id: $tileset_job."
    else
        echo "[ERR] Failed to publish tileset $tileset_id. [1]"
        exit 1
    fi
}

# Check if the tileset_id is already in use. If so, skip the creation of tileset and jump to tileset publish.
tileset_existing=false
echo "" > tempfile
curl -X GET https://api.mapbox.com/tilesets/v1/$mapbox_user?type=vector\&access_token=$mapbox_access_token \
    | jq -r '.[] | .id' >> tempfile

while read line
do
    if [ "$line" == "$mapbox_user.$tileset_id" ]
    then
        tileset_existing=true
        break
    fi
done < tempfile

if [ $tileset_existing == false ]
then
    create_tileset
    publish_tileset
else
    echo "[INFO] The tileset with the given name already exists. It will be replaced through the tileset publish process."
    publish_tileset
fi

# Watch for the completion of the tileset publish job
completed=false
while [ $completed == false ]
do
    sleep 3
    curl -s -X GET https://api.mapbox.com/tilesets/v1/$mapbox_user.$tileset_id/jobs/$tileset_job?access_token=$mapbox_access_token \
        | jq -r '.stage' > tempfile
    job_stage=`cat tempfile`
    echo $job_stage
    if [ $job_stage == processing ]
    then
        echo -n '. '
    elif [ $job_stage == success ]
    then
        completed=true
    else 
        echo "[ERR] Failed to publish tileset $tileset_id. [2]"
        exit 1
    fi
done
echo
echo "[INF] The tileset named $mapbox_user.$tileset_id has been published."

# Remove tempfile and exit. To create a mapbox style, uncomment the next two lines and edit the style specification below.
rm datafile
rm tempfile
exit 0

# Define style specification.
tileset_url="mapbox://$mapbox_user.$tileset_id"
tileset_style_json=`cat <<EOF
{
    "version": 8,
    "name": "$tileset_style_id",
    "sources": {
        "$tileset_id": {
            "type": "vector",
            "url": "$tileset_url"
        }
    },
    "layers": [ ],
    "visibility": "private",
    "draft": true
}
EOF
`

# To create a mapbox style from the tileset, uncomment the exit command above.
curl -X POST https://api.mapbox.com/styles/v1/$mapbox_user?access_token=$mapbox_access_token \
     -H "Content-Type: application/json" \
     -d "$tileset_style_json" 

# Remove tempfile and exit
rm datafile
rm tempfile
exit 0

