#!/bin/bash

#set -e
#
package=hook_rhcos.sh
VMID=$1
PHASE=$2
FORCE=""
OUTPUT=false
TYPE=ign

while test $# -gt 2; do
  case "$3" in
    -h)
      echo "$package - generate ignition or machineconfigs files for coreos"
      echo " "
      echo "$package VMID PHASE [options]"
      echo " "
      echo "options:"
      echo "-o			  output to stndout"
      echo "-t			  ign, machineconfig"
      echo "-h                    show brief help"
      echo "-f 	                  force regeneration if ign file"
      exit 0
      ;;
   -t)
      shift
      if test $# -gt 0 ; then
        export TYPE=$3
      else
        echo "no format specified"
        exit 1
      fi
      shift
      ;;
    -o)
      export OUTPUT=true
      shift
      ;;
    -f)
      export FORCE=true
      shift
      ;;
    *)
       
      break
      ;;
  esac
done

# global vars
COREOS_TMPLT=/var/lib/vz/snippets/rhcos-base-template.yaml
COREOS_IMPORT_TEMPLATE=/var/lib/vz/snippets/rhcos-import-template.yaml
COREOS_FILES_PATH=/etc/pve/rhcos-pve/coreos
YQ="/usr/local/bin/yq -e -P "
TEMPDIR="/tmp"

# ==================================================================================================================================================================
# functions()
#
setup_butane()
{
	local BT_VER=0.22.0
	local ARCH=x86_64
	local OS=unknown-linux-gnu
	local DOWNLOAD_URL=https://github.com/coreos/butane/releases/download
	
	[[ -x /usr/local/bin/butane ]]&& [[ "x$(/usr/local/bin/butane --version | awk '{print $NF}')" == "x${BT_VER}" ]]&& return 0
	echo "Setup Butane..."
	rm -f /usr/local/bin/butane
	wget --quiet --show-progress ${DOWNLOAD_URL}/v${BT_VER}/butane-${ARCH}-${OS} -O /usr/local/bin/butane
	chmod 755 /usr/local/bin/butane
}
setup_butane

setup_yq()
{
        local VER=4.44.2

        [[ -x /usr/bin/wget ]]&& download_command="wget --quiet --show-progress --output-document"  || download_command="curl --location --output"
        [[ -x /usr/local/bin/yq ]]&& [[ "x$(/usr/local/bin/yq --version | awk '{print $NF}')" == "xv${VER}" ]]&& return 0
        echo "Setup yaml parser tools yq..."
        rm -f /usr/local/bin/yq
        ${download_command} /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${VER}/yq_linux_amd64
        chmod 755 /usr/local/bin/yq
}
setup_yq

cleanup()
{
	${WORKDIR:-false} || [[ -d $WORK_DIR ]] && {
		rm -rf ${WORK_DIR}
		echo -n "Cleaning up... "
		echo "[done]"
	}
}

# ==================================================================================================================================================================
# pre-start()

pre-start()
{
	instance_id="$(qm cloudinit dump ${VMID} meta | ${YQ} '.instance-id')"
	# Set the Type output.  If type yaml were expecting a machineconfig
	([[ ${TYPE} != "ign" ]]) && TYPE="yaml"

	mkdir -p ${COREOS_FILES_PATH} || exit 1
	
	echo "CoreOS: Generate Machine Config File... "
	# same cloudinit config 
	([[ ${FORCE} == "true" ]] || ([[ -e ${COREOS_FILES_PATH}/${VMID}.id ]] && [[ "x${instance_id}" != "x$(cat ${COREOS_FILES_PATH}/${VMID}.id)" ]])) && {
		rm -f ${COREOS_FILES_PATH}/${VMID}.ign # cloudinit config change
		rm -f ${COREOS_FILES_PATH}/${VMID}-machineconfig.yaml
	}
	[[ -e ${COREOS_FILES_PATH}/${VMID}.ign ]] || [[ -e ${COREOS_FILES_PATH}/${VMID}-machineconfig.yaml ]] && echo "Ignition File for VM${VMID} already exists. Use -f to force recreation" && exit 0 # already done

	# check config
	cipasswd="$(qm cloudinit dump ${VMID} user | ${YQ} '.password' 2> /dev/null)" || true # can be empty
	[[ "x${cipasswd}" != "x" ]]&& VALIDCONFIG=true
	${VALIDCONFIG:-false} || [[ "x$(qm cloudinit dump ${VMID} user | ${YQ} '.ssh_authorized_keys[]')" == "x" ]] || VALIDCONFIG=true
	${VALIDCONFIG:-false} || {
		echo "CoreOS: you must set passwd or ssh-key before start VM${VMID}"
		exit 1
	}

	#check ign_{tagname} for importing 
	[[ -e ${COREOS_IMPORT_TEMPLATE} ]] || {
		echo "Missing Import Template File"
		exit 1
	}
	importserver="$(${YQ} '.merge[] | to_entries[].value' ${COREOS_IMPORT_TEMPLATE} 2> /dev/null)"
	[[ "x${importserver}" == "x" ]] && echo "Missing Merge source in ${COREOS_IMPORT_TEMPLATE}" && exit 1 

	${VALIDIGNTAG:-false} || [[ "x$(qm config ${VMID} | grep -q 'tags' | grep -q 'ign_' )" == "x" ]] && VALIDIGNTAG=true && TAGTYPE='ign'
	${VALIDISOTAG:-false} || [[ "x$(qm config ${VMID} | grep -q 'tags' | grep -q 'iso_' )" == "x" ]] && VALIDISOTAG=true && TAGTYPE='iso'
	${VALIDIGNTAG:-false} && ${VALIDISOTAG:-false} || {
		echo "CoreOS: You must specifiy a 'ign_TAG' where TAG matches ignition file at ${importserver}"
		exit 1
	}

	igntag="$(qm config ${VMID} | grep 'tags' | ${YQ} '.tags' 2> /dev/null | grep ${TAGTYPE}'_' | sed -e 's/'${TAGTYPE}'_//')" || exit 1
	#Get All the tags
	#readarray tags < <(qm config ${VMID} | grep 'tags' | ${YQ} '.tags | split(";")')
	#for tag in "${tags[@]}"; do  echo $tag | grep 'ign_' | sed -e 's/^- ign_//g'; done
	[[ ${TYPE} == "yaml" ]] && VARIANT="openshift" || VARIANT="fcos" 
	[[ ${VARIANT} == "openshift" ]] && VERSION='4.17.0' || VERSION='1.5.0' 
	#echo -e "CoreOS: Applying Merge for Ignition tag: $(echo ${importserver} | sed -e 's/TAG/'${igntag}'/')"
	echo -e "# This file is managed by RHCOS hook-script. Do not edit.\n" > ${COREOS_FILES_PATH}/${VMID}.yaml
	echo -e "---\nvariant: ${VARIANT}\nversion: ${VERSION} " >> ${COREOS_FILES_PATH}/${VMID}.yaml
	[[ -e "${COREOS_IMPORT_TEMPLATE}" &&  -n "${igntag}" ]]&& {
		[[ ${VARIANT} == 'fcos' ]] && {
			echo -n "CoreOS: Generate yaml config block... "
			echo -e "ignition:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
			echo -e "  config:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
			sed -e "s/TAG/${igntag}/g" -- "${COREOS_IMPORT_TEMPLATE}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
			echo "[done]"
		}
	}
	[[ ${VARIANT} == "openshift" ]] && {
		echo -n "CoreOS: Generate yaml metadata block... "
		echo -e "metadata:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo -e "  name: 99-${igntag}-pve" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo -e "  labels:\n    machineconfiguration.openshift.io/role: ${igntag}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "[done]"
	}

	[[ ${VARIANT} == "fcos" ]] && ciuser="$(qm cloudinit dump ${VMID} user 2> /dev/null | grep ^user: | awk '{print $NF}')" || ciuser="core"
		
	echo -n "CoreOS: Generate yaml users block... "
	echo -e "# user\npasswd:\n  users:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "    - name: \"${ciuser:-admin}\"" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	[[ ${VARIANT} == "fcos" ]] && {
		echo "      gecos: \"CoreOS Administrator\"" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "      password_hash: '${cipasswd}'" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo '      groups: [ "sudo", "adm", "wheel", "systemd-journal" ]' >> ${COREOS_FILES_PATH}/${VMID}.yaml
	}
	echo '      ssh_authorized_keys:' >> ${COREOS_FILES_PATH}/${VMID}.yaml
	qm cloudinit dump ${VMID} user | ${YQ} '.ssh_authorized_keys[]' | sed -e 's/^/        - "/' -e 's/$/"/' >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "[done]"
	
	echo -n "CoreOS: Generate yaml hostname block... "
	hostname="$(qm cloudinit dump ${VMID} user | ${YQ} '.hostname' 2> /dev/null)"
	echo -e "# network\nstorage:\n  files:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "    - path: /etc/hostname" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "      mode: 0644" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "      overwrite: true" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "      contents:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo "        inline: |" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	echo -e "          ${hostname,,}\n" >> ${COREOS_FILES_PATH}/${VMID}.yaml 
	echo "[done]"
	
	echo -n "CoreOS: Generate yaml network block... "
	network_yaml="$(qm cloudinit dump ${VMID} network | yq -o json 2> /dev/null)"
	netcards="$(echo ${network_yaml} | ${YQ} -p=json '.config[] | select(.type == "physical").name' 2> /dev/null | wc -l)"
	nameservers="$( echo ${network_yaml} | ${YQ} -p=json '.config[] | select(.type == "nameserver").address[]' | paste -s -d ";" -)"
	searchdomain="$(echo ${network_yaml} | ${YQ} -p=json '.config[] | select(.type == "nameserver").search[]' | paste -s -d ";" -)"
	for (( i=O; i<${netcards}; i++ ))
	do
		ipv4="" netmask="" gw="" macaddr="" # reset on each run
		ipv4="$(echo ${network_yaml} | ${YQ} -p=json '.config[${i}].subnets[0].address' 2> /dev/null)" || continue # dhcp
		netmask="$(echo ${network_yaml} | ${YQ} -p=json '.config[${i}].subnets[0].netmask' 2> /dev/null)"
		gw="$(echo ${network_yaml} | ${YQ} -p=json '.config[${i}].subnets[0].gateway' 2> /dev/null)" || true # can be empty
		macaddr="$(echo ${network_yaml} | ${YQ} -p=json '.config[${i}].mac_address' 2> /dev/null)"
		# ipv6: TODO

		echo "    - path: /etc/NetworkManager/system-connections/net${i}.nmconnection" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "      mode: 0600" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "      overwrite: true" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "      contents:" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "        inline: |" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          [connection]" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          type=ethernet" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          id=net${i}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          #interface-name=eth${i}\n" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo -e "\n          [ethernet]" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          mac-address=${macaddr}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo -e "\n          [ipv4]" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          method=manual" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          addresses=${ipv4}/${netmask}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "          gateway=${gw}" >> ${COREOS_FILES_PATH}/${VMID}.yaml 
		echo "          dns=${nameservers}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo -e "          dns-search=${searchdomain}\n" >> ${COREOS_FILES_PATH}/${VMID}.yaml
	done
	echo "[done]"

	[[ -e "${COREOS_TMPLT}" ]]&& {
		echo -n "CoreOS: Generate yaml template block... "
		cat "${COREOS_TMPLT}" >> ${COREOS_FILES_PATH}/${VMID}.yaml
		echo "[done]"
	}


	#[[ ${OUTPUT} != "true" ]] && OUTPUT=" --output ${COREOS_FILES_PATH}/${VMID}.${TYPE}"
	#echo $OUTPUT

       # [[ ${OUTPUT} ]] || butane_command="${butane_command} --strict --pretty --output "
       	OUTNAME=${VMID}.ign
	[[ ${VARIANT} == "openshift" ]] && OUTNAME="${VMID}-machineconfig.yaml"
	echo -n "CoreOS: Generate ${OUTNAME}... "
	/usr/local/bin/butane --strict \
	       --pretty --output ${COREOS_FILES_PATH}/${OUTNAME} ${COREOS_FILES_PATH}/${VMID}.yaml


	[[ $? -eq 0 ]] || {
		echo "[failed]"
		exit 1
	}
	echo "[done]"

	[[ ${OUTPUT} == "true" ]] && {
		clear
		cat ${COREOS_FILES_PATH}/${OUTNAME}
	}
	
	# save cloudinit instanceid
	echo "${instance_id}" > ${COREOS_FILES_PATH}/${VMID}.id
	
	boot=$(qm config ${VMID} | grep ^boot | sed -e 's/^[^=]*=//g' | cut -d ';' -f 1) || true # can be empty
	${ISOLIVEBOOT:-false} || [[ "x${boot}" == "xide3" ]] && ISOLIVEBOOT=true
	if [[ ${ISOLIVEBOOT} ]]; then	
		#setup_podman
		# Checking for ISO attached to ide3 for ignition injection
		isofile=$(qm config ${VMID} --current | grep '^ide3' | ${YQ} '.ide3' 2> /dev/null | cut -d ',' -f 1) || true
		[[ "x${isofile}" != "xnull" ]] && {
			isopath=$(pvesm path ${isofile})
			echo -n "CoreOS: Live CD Detected: `basename ${isopath}`... "
			echo "[done]"

			DIR="$( cd "$( dirname "${COREOS_FILES_PATH}" )" && pwd )"
			WORK_DIR=`mktemp -d -p "$DIR"`
			[[ ! ${WORK_DIR} || ! -d ${WORK_DIR} ]] && echo "Unable to create temp dir" && exit 1
			
			trap cleanup EXIT
		    
			cp ${COREOS_FILES_PATH}/${VMID}.ign ${WORK_DIR}/config.ign
			coreos_installer="podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release'"
			cd $WORK_DIR && ${coreos_installer} iso ignition embed -fi config.ign ${isopath}
			exit 1
		}

	else 
		# check vm config (no args on first boot)
		qm config ${VMID} --current | grep -q ^args || {
			echo -n "Set args com.coreos/config on VM${VMID}... "
			rm -f /var/lock/qemu-server/lock-${VMID}.conf
			pvesh set /nodes/$(hostname)/qemu/${VMID}/config --args "-fw_cfg name=opt/com.coreos/config,file=${COREOS_FILES_PATH}/${VMID}.ign" 2> /dev/null || {
				echo "[failed]"
				exit 1
			}
			touch /var/lock/qemu-server/lock-${VMID}.conf

			# hack for reload new ignition file
			echo -e "\nWARNING: New generated CoreOS ignition settings, we must restart vm..."
			qm stop ${VMID} && sleep 2 && qm start ${VMID}&
			exit 1
		}
	fi	
}


# ==================================================================================================================================================================
# post-start()

post-start()
{
	echo ""
}

# ==================================================================================================================================================================
# post-start()

pre-stop()
{
	echo ""
}


# ==================================================================================================================================================================
# post-start()

post-stop()
{
	echo ""
}

main()
{	
	echo "---------------------------------------------------------------------------------"
	echo "Current Phase: ${PHASE}"
	${PHASE}
}

main
exit 0
