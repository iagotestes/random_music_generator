#! /bin/bash
########
####################################################################################################
#Script for randomization of musics in the current directory tree
#@author:	Iago Gomes
#@date:		08/03/2021
#@version:	1.0 (08/03/2021)
#@description:	
#The script fills an usb device with a list of randomized musics fetched from the directory 
#tree where it is executed. It also creates a log file with the musics fetched, for 
#the same musics shall not be repeated in the next execution.
#@observation:	ubuntu 20.04; GNU bash version 5.0.17
####################################################################################################


######################################## VARIABLES #################################################
MAX_FIT_TRY=3

DEVICE=""
DEVICE_TYPE=""
DEVICE_MOUNTED=""
DEVICE_DISK=""
DEVICE_NEW_MOUNT=""
DEVICE_SIZE=""

OUTPUT_DIR=""
LOGS=()
LOGS_DIR=""

NUM_MUSICS=0 
MUSICS=()
MUSICS_OUT=()

REGEX_VERIFY_DEVICES=""
####################################################################################################

function verify_devices()
{
	#VERIFY DEVICES WHICH THE DISK MODEL IS ( Flash Disk ) 
	aux=$(sudo fdisk -l | grep -iE 'Disk /dev/sd|Disk model' | awk 'NR%2{printf "%s",$0;next;}1' | grep -iE 'flash disk' | awk '{gsub(/\:/,"")}1'  | awk '{print $2"."}' | awk 'NR%10{printf "%s|",$0;next;}1')
	if [ -z "$aux" ]; 
	then 
		REGEX_VERIFY_DEVICES=""
	else
		REGEX_VERIFY_DEVICES=${aux::-1}
	fi
}
 
function choose_device()
{	
	#ADD THE VERIFIED DEVICES IN THE DEVICE ARRAY 
	ARRAY_DEVICES=()	
	while IFS= read -r -d $'\n' line; do
		ARRAY_DEVICES+=( "$line" )	
	done < <( df | grep -iE "$REGEX_VERIFY_DEVICES" | awk '{print $0}' | awk '{print $1,$6}')

	#OFFERS USER SELECTION
	echo 'choose one: '
	select dev in "${ARRAY_DEVICES[@]}" 
	do
		if [ -z "$dev" ]; 
		then
			echo 'insert device and try again';
			exit 1
		else
			DEVICE=$dev
			echo device selected: $DEVICE
			break
		fi
	done
}

function generate_musics()
{
	SIZE_FREE_ACTUAL="$DEVICE_SIZE"
    NUM_MUSICS=`find . -type f -iname "*.mp3" | wc -l` 
    if [[ "$NUM_MUSICS" -eq 0 ]]; then 
		echo "NO MUSIC FOUND IN THE DIRECTORY OF SEARCH"
		exit 5
    else
        rm music_names  music_sizes  music_outputs 2> /dev/null
        
        touch music_names music_sizes music_outputs
        ## find . -type f -iname "*.mp3" -print0 | while IFS= read -r -d '' filename; do
        ##...
        ## done
        ## find . -type f -iname "*.mp3" -print0 -exec bash -c 'printf "%q\n" "$@"' sh {} +
        ##                                                                               \;

        find . -type f -iname "*.mp3" -print0 -exec bash -c 'printf "%q\n" "$@"' sh {} + >> music_names
    #   cat music_names | xargs -0 -I {} wc -c {} 2> /dev/null | awk '{print $1}' >>  music_sizes
        cat music_names | xargs -0 -I {} wc -c {} | awk '{print $1}' >>  music_sizes

        RANDOM_INDEXES=( $( seq 1 $NUM_MUSICS | shuf - ) )

    #loop start
        for index in "${RANDOM_INDEXES[@]}"; do 
            music_size_bytes=`sed -n "$index"p music_sizes`
            if [[ "$SIZE_FREE_ACTUAL" -gt "$music_size_bytes" ]] ; then 
                #UPDATE FREE SIZE
                SIZE_FREE_ACTUAL="$(( $SIZE_FREE_ACTUAL - $music_size_bytes ))"
                echo "DEVICE SIZE: $SIZE_FREE_ACTUAL"
                #COPY MUSIC NAME TO OUTPUT FILE
                sed -n "${index}p" music_names >> music_outputs  
            else
                #UPDATE THE NUMBER OF CHANCES TO FIT THE MUSIC IN THE OUTPUT
                MAX_FIT_TRY="$(($MAX_FIT_TRY-1))"
                if [[ "$MAX_FIT_TRY" -eq 0 ]]; then 
                    break;
                fi
            fi           
        done
       rm music_names music_sizes 
       wc -l music_outputs
    fi
    #sed -n 2199p music_* ## pega o que estiver na linha 2199 (contando a partir de 1) do arquivo music_*
}


function remove_music()
{
	index_del="$1"
	aux=("${MUSICS[@]}")
	MUSICS=()
	for i in "${!aux[@]}"; do
		if [[ "$index_del" -ne "$i" ]]; then
			MUSICS+=("${aux[$i]}")
		fi
	done
}

function clear_device()
{
	#ASK FOR PERMISSION TO FORMAT THE DEVICE
	var=""
	while [[ "$var" != "y" ]] && [[ "$var" != "n" ]]; do
		echo "To continue your device will be formated. Wish to continue? [y/n]"
		read var	
	done
		
	if [[ "$var" == "y" ]];
	then
		echo format
		if [ "${DEVICE_TYPE,,}" = "flash disk" ]; then #USB
			echo "flash disk"
			format_flash
			set_device_size	
		else
			echo "device type not compatible"
			exit 4
		fi
	else 
		echo format canceled
		exit 3
	fi
}

function format_flash()
{
	#UMOUNT THE FILESYSTEMS MOUNTED IN THE DEVICE DISK PARTITIONS 
        for part in "$DEVICE_DISK"?; 
	do
                sudo umount "$part";
        done

	#DELETE ALL FILESYSTEMS IN THE DEVICE
        sudo wipefs --all "$DEVICE_DISK"

	#CREATE A NEW SINGLE PARTITION 
        sudo parted -s -a optimal "$DEVICE_DISK" mklabel msdos mkpart primary 0% 100%
	
	#GENERATE A NAME FOR THE FILESYSTEM
        d=`date | awk '{print $1$2}'`
        d="MUS${d^^}"
	
	#CREATE A NEW MS-DOS FILESYSTEM FOR THE DEVICE'S NEW PARTITION
	DEVICE_MOUNTED="${DEVICE_DISK}1"
        sudo mkfs.vfat -n "$d" "$DEVICE_MOUNTED"
	
	#MOUNT THE FORMATED DEVICE
        sudo mkdir -p /media/"$USER"/"$d"
        DEVICE_NEW_MOUNT="/media/$USER/$d"
	sudo mount "${DEVICE_DISK}1" "$DEVICE_NEW_MOUNT"   # /media/"$USER"/"$d"
	

}

function set_device_size()
{
	#SETS THE DEVICE_SIZE VARIABLE TO THE MOUNTED DEVICE IN BYTES
	DEVICE_SIZE=`df -B1 "$DEVICE_MOUNTED" | awk '{print $4}' | tail -1`
	#check if is not a number
	if [ ! "$DEVICE_SIZE" -eq "$DEVICE_SIZE" ] 2>/dev/null; then
		echo "could not find device size"
		exit 4
	else
		echo "device size: $DEVICE_SIZE"	
	fi			

	
}

function set_device_type()
{
	#CATCHES THE PARTITION WHERE THE DEVICE IS MOUNTED	
	aux=`sudo echo $DEVICE | awk '{print $1}'`

	last_char_is_number="${aux: -1}"
	
	if [ "$last_char_is_number" -eq  "$last_char_is_number" ] 2>/dev/null; then 
		DEVICE_MOUNTED="$aux"
		aux="${aux::-1}"
	fi

	#SETS THE DEVICE DISK
	DEVICE_DISK="$aux"

	#RECOVER THE DEVICE TYPE
	ex="sudo fdisk -l | grep -A1 '$aux' | grep -v \"$aux\" | awk '{print \$3,\$4}' | cut -d \$'\\n' -f1"
	
	DEVICE_TYPE="$( eval $ex )"
	DEVICE_TYPE=` echo $DEVICE_TYPE | sed 's/ *$//g'`	

	echo device type: -\>"$DEVICE_TYPE"\<-
}

#function fill_device()
#{

#}

function create_or_read_logs()
{	
	#SEARCH FOR LOGS OF PREVIOUS USES TO AVOID REPETITION
	DIR_NAME="./LOGS_RM"
	LOGS_DIR="$DIR_NAME/logs"

	if [[ ! -d "$DIR_NAME" ]]; then
		mkdir "$DIR_NAME"
		echo -n "" > "$LOGS_DIR"
	elif [[ ! -f "$LOGS_DIR" ]]; then
		echo -n "" > "$LOGS_DIR"
	else
		#FILLS LOGS WITH THE ENTRIES OF THE FILE
		while IFS= read -r line; do
			LOGS+=( "$line" )
		done < <( cat "$LOGS_DIR" ) 
		echo "logs size: ${#LOGS[@]}"

	fi
		
}

function fill_folder()
{
	#TODO: CLEAN DIRECTORY IF IT IS EXISTS AND HAS MUSICS
	#CREATE FOLDER
	mkdir -p ./MUSICS_OUT
	
	#FILL FOLDER WITH COPYS OF THE MUSICS 
	#for sm in "${MUSICS_OUT[@]}"; do 
		cat music_outputs | xargs  -I  {} cp {} ./MUSICS_OUT/	
	#done

#	while IFS= read -r line; do
#		m=`echo "$line" | awk '{$1=""; print $0}'` 
 #       	cp "\"$m\"" ./MUSICS_OUT/
  #      done < <( $MUSICS_OUT[@] ) 
}

function main()
{
#	verify_devices
#	if [  -z "$REGEX_VERIFY_DEVICES" ]
#	then
#		echo 'insert device and try again';
#		exit 1
	
#	else 
	#	echo '###################SELECT DEVICE#######################';
	#	choose_device # set DEVICE selected
	#	set_device_type # set DEVICE_TYPE (Flash Disk); set DEVICE_MOUNTED /dev/sdXN; set DEVICE_DISK /dev/sdX
	#	if [ -z "$DEVICE_TYPE" ]; then 
	#		echo 'device type not identified';
	#		exit 2
	#	fi
	#	clear_device # set size and format DEVICE
	#	create_or_read_logs # fills LOGS and sets LOGS_DIR
		
		# DEVICE_SIZE=8036290560
    	DEVICE_SIZE=1900000000

		generate_musics  # (DEVICE_SIZE,LOGS)  reads LOGS fills: MUSICS, LOGS	#	output_into_dir(MUSICS) # optional: put the musics generated in a directory
		fill_folder
	#	fill_device()
		#TODO: UMOUNT DEVICE AND DELETE ITS MOUNTED FOLDER AND EJECT DISK
		# TODO: exit 0
#	fi
}

#main 

################################# PARSE ARGUMENTS #################################  

LOG_OPT="" # FULL: try to read logs from ./LOGS/, and does not use musics that already have hashes in there; 
           #       logs md5sum of musics resulting from the draw.
           # 
           # LOGONLY: logs md5sum of musics resulting from the draw.
           #
           # READONLY: try to read logs from ./LOGS/, and does not use musics that already have hashes in there; 

for i in "$@"
do 
case $i in 
    --log=*)
        LOG_OPT="${i#*=}"
        shift
        ;;

esac
done

echo "$LOG_OPT"
