#!/bin/bash

# Mapeo de números de plugin a nombres (ACTUALIZADO A 19 PLUGINS)
declare -a plugins_by_number=(
    [1]="com.gruposansimon.custom"          # Original ID 1
    [2]="lvewithholding"                    # Original ID 5
    [3]="net.frontuari.assetmaintenance"    # Original ID 6
    [4]="net.frontuari.bankcharges"         # Original ID 7
    [5]="net.frontuari.bpallocation"        # Original ID 8
    [6]="net.frontuari.consignment"         # Original ID 9
    [7]="net.frontuari.custom"              # Original ID 10
    [8]="net.frontuari.ftucreatefrom"       # Original ID 11
    [9]="net.frontuari.lvecustomprocess"    # Original ID 12
    [10]="net.frontuari.lvedocumentcontrol" # Original ID 13
    [11]="net.frontuari.mfg"                # Original ID 14
    [12]="net.frontuari.mfta"               # Original ID 15
    [13]="net.frontuari.payselection"       # Original ID 16
    [14]="net.frontuari.pickingdairy"       # Original ID 17
    [15]="net.frontuari.recordweight"       # Original ID 18
    [16]="net.frontuari.slaughterhousecontrol" # Original ID 19
    [17]="net.frontuari.statementmatch"     # Original ID 20
    [18]="net.frontuari.importdataprocess"
    [19]="net.frontuari.budget"
)

# Declarar arrays asociativos para dependencias
declare -A dependencies
declare -A reverse_dependencies
declare -A in_degree

# Inicializar estructuras de datos
for i in "${!plugins_by_number[@]}"; do
    plugin_name="${plugins_by_number[i]}"
    if [[ -n "$plugin_name" ]]; then 
        dependencies["$plugin_name"]=""
        reverse_dependencies["$plugin_name"]=""
        in_degree["$plugin_name"]=0
    fi
done

# Configurar dependencias según la tabla proporcionada
set_dependencies() {
    set_dep 1  "13,7,3,15,16,11,1"
    set_dep 2  "7,2"
    set_dep 3  "7,3"
    set_dep 4  "7,4"
    set_dep 5  "7,5"
    set_dep 6  "7,6"
    set_dep 7  "-"
    set_dep 8  "7,8"
    set_dep 9  "7,9"
    set_dep 10 "7,10"
    set_dep 11 "7,11"
    set_dep 12 "7,13,12"
    set_dep 13 "7"
    set_dep 14 "7,13,15"
    set_dep 15 "7,13"
    set_dep 16 "7,11,15,13,16"
    set_dep 17 "7,17"
    set_dep 18 "7"
    set_dep 19 "-"
}

set_dep() {
    local plugin_num=$1 
    local dep_str=$2    
    local plugin_name="${plugins_by_number[plugin_num]}"

    if [[ -z "$plugin_name" ]]; then
        echo "Advertencia CRÍTICA: No se encontró el plugin para el NUEVO ID $plugin_num en set_dep. Revisa 'plugins_by_number'."
        return
    fi
    
    IFS=',' read -ra dep_nums <<< "$dep_str"
    for dep_id_in_string in "${dep_nums[@]}"; do 
        if [[ "$dep_id_in_string" == "-" ]]; then
            continue
        fi
        
        if ! [[ "$dep_id_in_string" =~ ^[0-9]+$ ]]; then
            echo "Advertencia: ID de dependencia no numérico '$dep_id_in_string' encontrado para $plugin_name."
            continue
        fi

        if [[ "$dep_id_in_string" -eq "$plugin_num" ]]; then
            continue 
        fi
        
        dep_name="${plugins_by_number[dep_id_in_string]}"
        if [[ -n "$dep_name" ]]; then
            dependencies["$plugin_name"]+="$dep_name "
            reverse_dependencies["$dep_name"]+="$plugin_name "
        else
             echo "Advertencia: No se encontró el nombre para el NUEVO ID de dependencia '$dep_id_in_string' al procesar las dependencias de '$plugin_name'. Verifica que '$dep_id_in_string' sea un índice válido en 'plugins_by_number' (1-${#plugins_by_number[@]})."
        fi
    done
    
    dependencies["$plugin_name"]="${dependencies["$plugin_name"]% }"
}

# Configurar todas las dependencias
set_dependencies

# Inicializar in_degree
for plugin in "${!dependencies[@]}"; do
    if [[ -n "${dependencies["$plugin"]}" ]]; then
        in_degree["$plugin"]=$(echo "${dependencies["$plugin"]}" | wc -w)
    else
        in_degree["$plugin"]=0
    fi
done

# Inicializar cola con plugins sin dependencias
queue=()
for plugin in "${!in_degree[@]}"; do
    if [[ -n "$plugin" && "${in_degree["$plugin"]}" -eq 0 ]]; then 
        queue+=("$plugin")
    fi
done

# Orden topológico
order=()
while [[ ${#queue[@]} -gt 0 ]]; do
    current="${queue[0]}"
    queue=("${queue[@]:1}") 
    
    order+=("$current")
    
    if [[ -n "${reverse_dependencies["$current"]}" ]]; then
        for dependent in ${reverse_dependencies["$current"]}; do
            if [[ -n "$dependent" && -n "${in_degree["$dependent"]}" ]]; then 
                in_degree["$dependent"]=$((in_degree["$dependent"] - 1))
                if [[ "${in_degree["$dependent"]}" -eq 0 ]]; then
                    queue+=("$dependent")
                fi
            else
                echo "Advertencia: 'dependent' ($dependent) o su in_degree no está definido para el 'current' ($current)."
            fi
        done
    fi
done

# Verificar ciclo
actual_plugin_count_for_sorting=0
for i in "${!plugins_by_number[@]}"; do
    [[ -n "${plugins_by_number[i]}" ]] && actual_plugin_count_for_sorting=$((actual_plugin_count_for_sorting + 1))
done

if [[ ${#order[@]} -ne $actual_plugin_count_for_sorting ]]; then
    echo "Error: Dependencias cíclicas detectadas o no todos los nodos (${#order[@]} de $actual_plugin_count_for_sorting) fueron procesados. No se puede compilar."
    echo "Plugins en la cola final (si los hay): ${queue[@]}"
    echo "Plugins con in_degree > 0 restantes:"
    for plugin_name_check in "${!in_degree[@]}"; do
      if [[ ${in_degree["$plugin_name_check"]} -gt 0 ]]; then
        echo "  $plugin_name_check : ${in_degree[$plugin_name_check]} (depende de: ${dependencies["$plugin_name_check"]})"
      fi
    done
    exit 1
fi

# Construir lista de argumentos
cmd_args=()
for plugin_identifier_from_order in "${order[@]}"; do
    if [[ "$plugin_identifier_from_order" == "lvewithholding" ]]; then
        # Caso especial para lvewithholding
        # Su estructura es ../lvewithholding/net.frontuari.lvewithholding/pom.xml
        cmd_args+=("../lvewithholding/net.frontuari.lvewithholding")
    elif [[ "$plugin_identifier_from_order" == "net.frontuari.importdataprocess" ]]; then
        # Nuevo caso especial para importdataprocess
        cmd_args+=("../importdataprocess/net.frontuari.importdataprocess")
    else

        cmd_args+=("../${plugin_identifier_from_order}/${plugin_identifier_from_order}")
    fi
done

# Ejecutar el comando de compilación
echo "Compilando plugins en el orden correcto (${#cmd_args[@]} plugins)..."
echo "Comando a ejecutar: ./plugin-builder ${cmd_args[@]}" # Para depurar el comando
 ./plugin-builder "${cmd_args[@]}"

echo "Compilación completada."