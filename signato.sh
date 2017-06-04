#!/bin/bash
echo "######################################################"
echo "#                       signato                      #"
echo "# Semi-automated apple mail html signature installer #"
echo "#                                                    #"
echo "######################################################"
echo
# Check array support in bash
arrtest[0]='test' || (echo 'Failure: arrays not supported in this version of bash.' && exit 2)

# Expand the tilde
userDir=~

signatureFile="signature.html"
targetString="(signato)"
unlockOnly=false

# Parse the params
while [ "$1" != '' ]
  do
    [ "$1" == "-s" ] && signatureFile="$2" && shift && shift
    [ "$1" == "-p" ] && targetString=$2 && shift && shift
    [ "$1" == "-u" ] && unlockOnly=true && shift
done

echo "Placeholder text is \"$targetString\""
if [ "$unlockOnly" == "false" ]; then
	# If we do not just unlock the file, we need a signature source
	if [ ! -f "$signatureFile" ]; then
		echo "No signature html file found next to this script."
		echo "Place a file named \"signature.html\" in the same folder and try again"
		echo "or pass a file name as parameter: signato.sh -s filename.html"
		exit 1
	else 
		# Read the signature html
		htmlSignature=$(cat "$signatureFile")
		echo "Loaded HTML signature from \"$signatureFile\""
	fi 
else 
	echo "Will only unlock matched signature files"
fi

# A list of possible folders for the signatures, all relative to the user directory
localSigFolderList=(
	# OS X 10.10
     'Library/Mail/V2/MailData/Signatures'
     # OS X 10.11
     'Library/Mail/V3/MailData/Signatures'
     # OS X 10.12
     'Library/Mail/V4/MailData/Signatures'
   )

cloudigFolderList=(
	# OS X 10.10
     'Library/Mobile Documents/com~apple~mail/Data/MailData/Signatures'
     # OS X 10.11
     'Library/Mobile Documents/com~apple~mail/Data/V3/MailData/Signatures'
     # OS X 10.12
     'Library/Mobile Documents/com~apple~mail/Data/V4/Signatures'
   )

# Ask user whether using iCloud or not
echo -e "\nAre you using iCloud to sync your mail signatures?"
usingCloud=""

while [ "$usingCloud" != "0" ] && [ "$usingCloud" != "1" ]; do
	echo "Press 1 for yes and 0 for no: "
	read -n 1 usingCloud
done

folderList=()
if [ "$usingCloud" == "1" ]; then
	echo " => Using cloud-synced signature folder"
	folderList=( "${cloudigFolderList[@]}" )
elif [ "$usingCloud" == "0" ]; then
	echo " => Using local signature folder"
	folderList=( "${localSigFolderList[@]}" )
else
	echo "Invalid selection"
	exit 1
fi

# Find a directory that fit's our needs
targetFolder=""
for i in "${folderList[@]}"
do
	if [ -d "$userDir/$i" ]; then
		targetFolder="$userDir/$i"
	fi
done

if [ "$targetFolder" == "" ]; then
	echo "Unable to find signature folder"
	exit 1
fi
echo "Signature folder: $targetFolder"

# Check that Mail app is closed
echo "Checking Apple Mail app status"
echo
while [ true ]; do
runningProcesses=$(ps -ax | grep "/Applications/Mail.app/" | wc -l | bc)
if [ $runningProcesses -le 1 ]; then
	break
fi
echo -en "\033[1A"
read -p "Apple Mail is still running, please close it and press [ENTER]"
done

# Remove potential leftover temp files from previous runs
rm "$targetFolder/signato_temp.txt" 2> /dev/null

totalCount=0
matchCount=0
# Iterate over the files and check the contents (using process substiution)
while IFS= read -r -d '' filename; do
	totalCount=$((totalCount + 1))
	grep -q "$targetString" "$filename"
	if [ $? -eq 0 ]
	then
		matchCount=$((matchCount + 1))
		# The file contains our target
		# Unlock the file
		chflags nouchg "$filename"

		if [ "$unlockOnly" == "true" ];then
			# In case we should only unlock the file, do not furhter stay in the while loop
			continue
		fi

		# Write the Mail signature header to a temp file
		awk '/^$/{exit} {print $0}' "$filename" > "$targetFolder/signato_temp.txt"
		# Put a new line at the end of the temp file
		echo >> "$targetFolder/signato_temp.txt"
		# Append the html signature to the temp file
		echo $htmlSignature >> "$targetFolder/signato_temp.txt"

		# Remove the old signature file
		rm "$filename"
		# Rename the temp file
		mv "$targetFolder/signato_temp.txt" "$filename"

		# Lock the file again in case we're on local mode
	    if [ ! "$usingCloud" == "1" ]; then
	    	chflags uchg "$filename"
	    fi
	fi
done < <(find "$targetFolder" -type f -name *.mailsignature -print0)

echo "Found $totalCount signature(s) in total."
if [ $matchCount -gt 0 ];then
	echo "$matchCount file(s) contained the placeholder"
	if [ "$unlockOnly" == "true" ];then
		echo "and have been unlocked."
	else 
		echo "and their content has been replaced with your HTML signature."
		echo "You may now start Apple Mail again"
	fi
	
else 
	echo "None of them contained the placeholder text."
fi
