#!/bin/bash
mkdir /tmp/firmware 
cd /tmp/firmware
# Máximo de procesos en paralelo
MAX_PARALLEL=5

# Obtener lista de archivos iwlwifi
mapfile -t files < <(curl -s https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain | \
  grep iwlwifi | grep href | cut -d \' -f 2)

total=${#files[@]}
done_count=0

# Función para mostrar progreso
show_progress() {
  percent=$(( done_count * 100 / total ))
  echo -ne "Progreso: ${percent}% (${done_count}/${total})\r"
}

# Cola de descargas
for line in "${files[@]}"; do
  # Lanzar wget en segundo plano
  wget -q "https://git.kernel.org${line}" &

  # Incrementar contador de procesos paralelos
  ((running++))

  # Cuando llega al límite, esperar que terminen todos
  if [[ $running -ge $MAX_PARALLEL ]]; then
    wait
    ((done_count+=running))
    show_progress
    running=0
  fi
done

# Esperar últimos procesos si quedan
wait
((done_count+=running))
show_progress
echo -e "\nDescarga completa."

# Instala firmwares
#sudo cp ./* /lib/firmware

# If the modprobe errors because it is in use, rebooting should also work
#sudo modprobe -r iwlwifi && sudo modprobe iwlwifi
# ensure the next time you boot it uses those firmware files
#sudo update-initramfs -u
