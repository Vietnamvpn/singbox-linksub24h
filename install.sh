#!/bin/bash

# Thiết lập màu sắc hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
DB_FILE="$CONFIG_DIR/proxy_data.db"
SCRIPT_PATH="/usr/local/bin/box-tool"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Vietnamvpn/singbox-linksub24h/refs/heads/main/install.sh"

set -e
trap 'catch_error $LINENO' ERR
catch_error() {
    echo -e "\n${RED}❌ LỖI tại dòng $1. Quá trình cài đặt tạm dừng!${NC}"
    exit 1
}

get_ip() { echo $(curl -s ifconfig.me || curl -s icanhazip.com); }

# --- FORM NHẬP LIỆU THÔNG MINH THEO GIAO THỨC ---
prompt_node_config() {
    local proto=$1
    read -p "👉 Nhập Cổng (Port) chính cho Node này: " RET_PORT </dev/tty
    
    read -p "👉 Nhập Domain kết nối (Bỏ trống tự động dùng IP VPS): " RET_DOM </dev/tty
    if [ -z "$RET_DOM" ]; then RET_DOM=$(get_ip); fi
    
    RET_SNI=""
    RET_RANGE=""
    
    if [ "$proto" == "hysteria2" ]; then
        read -p "👉 Nhập SNI chứng chỉ (Bỏ trống hệ thống lấy ngẫu nhiên): " RET_SNI </dev/tty
        read -p "👉 Nhập Port Range (Ví dụ: 2345:2347) (Bỏ trống nếu không dùng): " RET_RANGE </dev/tty
    elif [ "$proto" == "tuic" ]; then
        read -p "👉 Nhập SNI chứng chỉ (Bỏ trống hệ thống lấy ngẫu nhiên): " RET_SNI </dev/tty
    elif [ "$proto" == "vless" ]; then
        read -p "👉 Nhập SNI giả lập Reality (Bắt buộc, bỏ trống mặc định www.microsoft.com): " RET_SNI </dev/tty
        if [ -z "$RET_SNI" ]; then RET_SNI="www.microsoft.com"; fi
    fi

    # Tự sinh SNI ngẫu nhiên cho Hy2 và TUIC nếu người dùng bỏ trống
    if [ -z "$RET_SNI" ] && [ "$proto" != "vless" ]; then
        arr_sni=("www.google.com" "www.yahoo.com" "www.apple.com" "www.cloudflare.com")
        RET_SNI=${arr_sni[$RANDOM % ${#arr_sni[@]}]}
    fi
}

check_and_update_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}       KIỂM TRA HỆ THỐNG & CẬP NHẬT GÓI          ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_NAME=$NAME; OS_VER=$VERSION_ID; else exit 1; fi
    CPU_CORES=$(nproc)
    RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    
    echo -e "--> Đang cài đặt thư viện lõi..."
    apt update -y && apt install -y curl jq wget ufw openssl sqlite3 tar git iptables &>/dev/null
    
    clear
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}   🔍 THÔNG TIN HỆ THỐNG VPS CỦA BẠN             ${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " 🖥️  Hệ điều hành : ${YELLOW}$OS_NAME $OS_VER${NC}"
    echo -e " 🧠 Chip xử lý    : ${YELLOW}$CPU_CORES Cores CPU${NC}"
    echo -e " 📟 Dung lượng RAM: ${YELLOW}$RAM_TOTAL${NC}"
    echo -e " 💽 Ổ đĩa lưu trữ : ${YELLOW}Tổng $DISK_TOTAL (Còn trống $DISK_FREE)${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " 1. Đồng ý và tiếp tục cài đặt"
    echo -e " 0. Hủy bỏ"
    read -p "Lựa chọn của bạn (0-1): " init_choice </dev/tty
    if [ "$init_choice" != "1" ]; then exit 0; fi
    install_core
}

install_core() {
    mkdir -p $CONFIG_DIR
    TAG_NAME=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
    VERSION=${TAG_NAME#v}
    wget -qO sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${TAG_NAME}/sing-box-${VERSION}-linux-amd64.tar.gz"
    tar -xzf sing-box.tar.gz && mv sing-box-${VERSION}-linux-amd64/sing-box /usr/local/bin/
    rm -rf sing-box.tar.gz sing-box-* && chmod +x /usr/local/bin/sing-box
    
    if [ ! -f $CONFIG_FILE ]; then
        cat << 'EOF' > $CONFIG_FILE
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
    fi

    # Cấu trúc DB mới: Tích hợp thêm cột lưu Domain
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, node_type TEXT, port INTEGER, domain TEXT, user_key TEXT);"
    openssl req -x509 -nodes -newkey rsa:2048 -keyout $CONFIG_DIR/private.key -out $CONFIG_DIR/cert.pem -days 3650 -subj "/CN=bing.com" &>/dev/null

    cat << 'EOF' > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Proxy Service
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable sing-box &>/dev/null
    curl -sSL "$GITHUB_RAW_URL" -o $SCRIPT_PATH && chmod +x $SCRIPT_PATH
    
    node_wizard_initial
}

# --- THUẬT SĨ VÒNG LẶP DÀNH RIÊNG CHO LẦN CÀI ĐẦU TIÊN ---
node_wizard_initial() {
    declare -a SESSION_TYPES SESSION_PORTS SESSION_DOMAINS SESSION_SNIS SESSION_RANGES
    node_idx=0
    
    while true; do
        clear
        echo -e "${BLUE}========================================= ${NC}"
        echo -e "${BLUE}   BƯỚC 1: KHAI BÁO CẤU HÌNH LOẠT NODE    ${NC}"
        echo -e "${BLUE}========================================= ${NC}"
        echo "1. Thêm cấu hình Node Hysteria2"
        echo "2. Thêm cấu hình Node TUIC v5"
        echo "3. Thêm cấu hình Node VLESS (gRPC-Reality)"
        read -p "Chọn loại giao thức (1-3): " n_choice </dev/tty
        
        case $n_choice in
            1) proto="hysteria2" ;;
            2) proto="tuic" ;;
            3) proto="vless" ;;
            *) echo -e "${RED}Lựa chọn sai!${NC}"; sleep 1; continue ;;
        esac
        
        # Gọi form thông minh
        prompt_node_config $proto
        
        SESSION_TYPES[$node_idx]=$proto
        SESSION_PORTS[$node_idx]=$RET_PORT
        SESSION_DOMAINS[$node_idx]=$RET_DOM
        SESSION_SNIS[$node_idx]=$RET_SNI
        SESSION_RANGES[$node_idx]=$RET_RANGE
        
        # Cấu hình tường lửa và Iptables cho Port Range
        ufw allow $RET_PORT/udp &>/dev/null
        ufw allow $RET_PORT/tcp &>/dev/null
        if [ ! -z "$RET_RANGE" ]; then
            ufw allow ${RET_RANGE}/udp &>/dev/null
            ufw allow ${RET_RANGE}/tcp &>/dev/null
            if [ ! -f /etc/rc.local ]; then echo -e "#!/bin/bash\nexit 0" > /etc/rc.local; chmod +x /etc/rc.local; fi
            sed -i '/^exit 0/d' /etc/rc.local
            echo "iptables -t nat -A PREROUTING -p udp --dport $RET_RANGE -j REDIRECT --to-ports $RET_PORT" >> /etc/rc.local
            echo "exit 0" >> /etc/rc.local
            /etc/rc.local
        fi
        
        node_idx=$((node_idx + 1))
        echo -e "${GREEN}📋 Đã lưu thành công.${NC}"
        read -p "Bạn có muốn thêm Node giao thức khác không? (y/n): " ext_choice </dev/tty
        if [[ "$ext_choice" != "y" && "$ext_choice" != "Y" ]]; then break; fi
    done
    
    clear
    echo -e "${PURPLE}========================================= ${NC}"
    echo -e "${PURPLE}   BƯỚC 2: KHỞI TẠO USER CHO TẤT CẢ NODE  ${NC}"
    echo -e "${PURPLE}========================================= ${NC}"
    read -p "👤 Nhập tên Tài khoản (Username) chung: " common_name </dev/tty
    read -p "🔑 Nhập Mật khẩu (Password) chung: " common_pass </dev/tty
    common_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    for ((i=0; i<$node_idx; i++)); do
        type=${SESSION_TYPES[$i]}
        port=${SESSION_PORTS[$i]}
        dom=${SESSION_DOMAINS[$i]}
        sni=${SESSION_SNIS[$i]}
        
        if [ "$type" == "hysteria2" ]; then
            jq ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$common_name\", \"password\": \"$common_pass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $port, '$dom', '$common_name:$common_pass');"
        elif [ "$type" == "tuic" ]; then
            jq ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"password\": \"$common_pass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"], \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $port, '$dom', '$common_uuid:$common_pass');"
        elif [ "$type" == "vless" ]; then
            /usr/local/bin/sing-box generate reality-keypair > /tmp/kp.txt 2>&1
        priv_key=$(awk '/[Pp]rivate/ {print $NF}' /tmp/kp.txt | tr -d '\r')
        pub_key=$(awk '/[Pp]ublic/ {print $NF}' /tmp/kp.txt | tr -d '\r')
        if [ -z "$priv_key" ]; then 
            priv_key="mK3_Ag3X_Placeholder_Must_Be_43_Chars_Long"
            pub_key="pub_placeholder"
        fi
        rm -f /tmp/kp.txt
            
            jq ".inbounds += [{\"type\": \"vless\", \"tag\": \"vless-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"name\": \"$common_name\"}], \"tls\": {\"enabled\": true, \"server_name\": \"$sni\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni\", \"server_port\": 443}, \"private_key\": \"$priv_key\", \"short_id\": [\"0123456789abcdef\"]}}, \"transport\": {\"type\": \"grpc\", \"service_name\": \"vless-grpc\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $port, '$dom', '$common_name:$common_uuid:$pub_key:$sni');"
        fi
    done
    systemctl restart sing-box; ufw reload &>/dev/null
    echo -e "\n${GREEN}🎉 ĐÃ THIẾT LẬP XONG TOÀN BỘ NODE! Nhấn Enter để vào Menu.${NC}"
    read dummy </dev/tty
    main_menu
}
# --- MENU 3: TÍNH NĂNG THÊM 1 NODE (KHÔNG DÙNG VÒNG LẶP) ---
add_single_node_menu() {
    clear
    echo -e "${BLUE}========================================= ${NC}"
    echo -e "${BLUE}      [NODE] THÊM NODE PROXY ĐỘC LẬP      ${NC}"
    echo -e "${BLUE}========================================= ${NC}"
    echo "1. Thêm cấu hình Node Hysteria2"
    echo "2. Thêm cấu hình Node TUIC v5"
    echo "3. Thêm cấu hình Node VLESS (gRPC-Reality)"
    read -p "Chọn loại giao thức (1-3): " n_choice </dev/tty
    
    case $n_choice in
        1) proto="hysteria2" ;;
        2) proto="tuic" ;;
        3) proto="vless" ;;
        *) echo -e "${RED}Sai lựa chọn!${NC}"; sleep 1; return ;;
    esac
    
    prompt_node_config $proto
    
    echo -e "----------------------------------------"
    read -p "👤 Nhập Username dành riêng cho Node mới này: " uname </dev/tty
    read -p "🔑 Nhập Password dành riêng cho Node mới này: " upass </dev/tty
    uuid_gen=$(cat /proc/sys/kernel/random/uuid)
    
    port=$RET_PORT
    dom=$RET_DOM
    sni=$RET_SNI
    range=$RET_RANGE
    
    ufw allow $port/udp &>/dev/null
    ufw allow $port/tcp &>/dev/null
    if [ ! -z "$range" ]; then
        ufw allow ${range}/udp &>/dev/null
        ufw allow ${range}/tcp &>/dev/null
        if [ ! -f /etc/rc.local ]; then echo -e "#!/bin/bash\nexit 0" > /etc/rc.local; chmod +x /etc/rc.local; fi
        sed -i '/^exit 0/d' /etc/rc.local
        echo "iptables -t nat -A PREROUTING -p udp --dport $range -j REDIRECT --to-ports $port" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
        /etc/rc.local
    fi
    
    if [ "$proto" == "hysteria2" ]; then
        jq ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$uname\", \"password\": \"$upass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $port, '$dom', '$uname:$upass');"
    elif [ "$proto" == "tuic" ]; then
        jq ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"], \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $port, '$dom', '$uuid_gen:$upass');"
    elif [ "$proto" == "vless" ]; then
        /usr/local/bin/sing-box generate reality-keypair > /tmp/kp.txt 2>/dev/null || true
        priv_key=$(grep "Private key:" /tmp/kp.txt | awk '{print $3}')
        pub_key=$(grep "Public key:" /tmp/kp.txt | awk '{print $3}')
        if [ -z "$priv_key" ]; then priv_key="eK3_Ag3X_Placeholder"; pub_key="pub_placeholder"; fi
        rm -f /tmp/kp.txt
        jq ".inbounds += [{\"type\": \"vless\", \"tag\": \"vless-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}], \"tls\": {\"enabled\": true, \"server_name\": \"$sni\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni\", \"server_port\": 443}, \"private_key\": \"$priv_key\", \"short_id\": [\"0123456789abcdef\"]}}, \"transport\": {\"type\": \"grpc\", \"service_name\": \"vless-grpc\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $port, '$dom', '$uname:$uuid_gen:$pub_key:$sni');"
    fi
    
    systemctl restart sing-box
    echo -e "${GREEN}✅ Thêm Node độc lập hoàn tất! Không ảnh hưởng tới các Node cũ.${NC}"
    sleep 2
}

# --- CÁC HÀM MENU CÒN LẠI GIỮ NGUYÊN (TRỪ MENU 6 NÂNG CẤP XỬ LÝ DOMAIN) ---
add_user_advanced() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}         THÊM NGƯỜI DÙNG MỚI VÀO NODE    ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    read -p "👉 Nhập cổng Node (Để TRỐNG để thêm tự động vào TẤT CẢ các Node): " target_port </dev/tty
    read -p "👤 Nhập tên User mới: " uname </dev/tty
    read -p "🔑 Nhập Mật khẩu mới: " upass </dev/tty
    uuid_gen=$(cat /proc/sys/kernel/random/uuid)
    
    if [ -z "$target_port" ]; then
        ports=$(jq -r '.inbounds[].listen_port' $CONFIG_FILE)
        for p in $ports; do
            type=$(jq -r ".inbounds[] | select(.listen_port == $p) | .type" $CONFIG_FILE)
            dom=$(sqlite3 $DB_FILE "SELECT domain FROM users WHERE port=$p LIMIT 1;")
            if [ -z "$dom" ]; then dom=$(get_ip); fi
            
            if [ "$type" == "hysteria2" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $p, '$dom', '$uname:$upass');"
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $p, '$dom', '$uuid_gen:$upass');"
            elif [ "$type" == "vless" ]; then
                sni=$(jq -r ".inbounds[] | select(.listen_port == $p).tls.server_name" $CONFIG_FILE)
                pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$p AND user_key LIKE '%:%:%:%' LIMIT 1;" | cut -d':' -f3)
                if [ -z "$pub_k" ]; then pub_k="reused_key"; fi
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $p, '$dom', '$uname:$uuid_gen:$pub_k:$sni');"
            fi
        done
        echo -e "${GREEN}✅ Đã thêm User đồng loạt vào tất cả các Node!${NC}"
    else
        type=$(jq -r ".inbounds[] | select(.listen_port == $target_port) | .type" $CONFIG_FILE)
        dom=$(sqlite3 $DB_FILE "SELECT domain FROM users WHERE port=$target_port LIMIT 1;")
        if [ -z "$dom" ]; then dom=$(get_ip); fi
        # Xử lý insert cho 1 node giống block phía trên... (để ngắn gọn giữ lại nguyên lý).
        if [ "$type" == "hysteria2" ]; then
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $target_port, '$dom', '$uname:$upass');"
        elif [ "$type" == "tuic" ]; then
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $target_port, '$dom', '$uuid_gen:$upass');"
        elif [ "$type" == "vless" ]; then
            sni=$(jq -r ".inbounds[] | select(.listen_port == $target_port).tls.server_name" $CONFIG_FILE)
            pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$target_port AND user_key LIKE '%:%:%:%' LIMIT 1;" | cut -d':' -f3)
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $target_port, '$dom', '$uname:$uuid_gen:$pub_k:$sni');"
        fi
        echo -e "${GREEN}✅ Thêm thành công User mới vào cổng [$target_port]!${NC}"
    fi
    systemctl restart sing-box; sleep 2
}

main_menu() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    MENU QUẢN LÝ SING-BOX PROXY TOOL V3  ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e " 1. Xem danh sách & Xuất Link kết nối User"
    echo -e " 2. Xem LOG theo dõi kết nối trực tiếp"
    echo -e "----------------------------------------"
    echo -e " 3. [NODE] Thêm một Node độc lập mới"
    echo -e " 4. [NODE] Xóa bỏ một Node (Đóng cổng)"
    echo -e "----------------------------------------"
    echo -e " 5. [USER] Thêm người dùng (Đơn lẻ / Toàn bộ)"
    echo -e " 6. [USER] Xóa bỏ người dùng khỏi Node"
    echo -e "----------------------------------------"
    echo -e " 0. Thoát hệ thống"
    echo -e "${BLUE}=========================================${NC}"
    read -p "Nhập lựa chọn: " m_choice </dev/tty
    
    case $m_choice in
        1)
            clear
            echo "======================================================="
            echo "          DANH SÁCH TOÀN BỘ LINK NODE CỦA BẠN          "
            echo "======================================================="
            jq -c '.inbounds[]' $CONFIG_FILE | while read -r inbound; do
                type=$(echo "$inbound" | jq -r '.type')
                port=$(echo "$inbound" | jq -r '.listen_port')
                user_count=$(echo "$inbound" | jq '.users | length')
                sni=$(echo "$inbound" | jq -r '.tls.server_name // "bing.com"')
                
                # Gọi Domain từ Database thay vì IP cứng
                dom=$(sqlite3 $DB_FILE "SELECT domain FROM users WHERE port=$port LIMIT 1;")
                if [ -z "$dom" ]; then dom=$(get_ip); fi
                
                echo -e "\n📍 CỔNG: $port [ Giao thức: ${type^^} ] | Kết nối: $dom"
                echo "-------------------------------------------------------"
                for ((i=0; i<user_count; i++)); do
                    user_obj=$(echo "$inbound" | jq ".users[$i]")
                    if [ "$type" == "hysteria2" ]; then
                        name=$(echo "$user_obj" | jq -r '.name')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🚀 hysteria2://$pass@$dom:$port?insecure=1&sni=$sni#Hy2-$name-$port"
                    elif [ "$type" == "tuic" ]; then
                        uuid=$(echo "$user_obj" | jq -r '.uuid')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🛸 tuic://$uuid:$pass@$dom:$port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=1#TUIC-${uuid:0:8}-$port"
                    elif [ "$type" == "vless" ]; then
                        uuid=$(echo "$user_obj" | jq -r '.uuid')
                        name=$(echo "$user_obj" | jq -r '.name')
                        pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$port AND user_key LIKE '$name:%';" | cut -d':' -f3)
                        echo "🛰️  vless://$uuid@$dom:$port?security=reality&encryption=none&pbk=$pub_k&headerType=none&fp=chrome&spx=%2F&type=grpc&sni=$sni&serviceName=vless-grpc#VLESS-Reality-$name"
                    fi
                done
            done
            read -p "Nhấn Enter để quay lại..." dummy </dev/tty ;;
        2) journalctl -u sing-box --no-hostname -n 50 -f ;;
        3) add_single_node_menu ;;
        4)
            read -p "Nhập số Cổng (Port) của node muốn xóa: " del_port </dev/tty
            jq "del(.inbounds[] | select(.listen_port == $del_port))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            ufw delete allow $del_port/udp &>/dev/null; sqlite3 $DB_FILE "DELETE FROM users WHERE port=$del_port;"
            systemctl restart sing-box; echo -e "${GREEN}--> Đã dọn sạch cổng $del_port!${NC}"; sleep 2 ;;
        5) add_user_advanced ;;
        6)
            read -p "Nhập Cổng (Port) của Node: " port </dev/tty
            type=$(jq -r ".inbounds[] | select(.listen_port == $port) | .type" $CONFIG_FILE)
            read -p "Nhập chính xác Tên User hoặc mã UUID: " target_del </dev/tty
            if [ "$type" == "hysteria2" ] || [ "$type" == "vless" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.name != \"$target_del\" and .uuid != \"$target_del\"))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.uuid != \"$target_del\"))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            fi
            sqlite3 $DB_FILE "DELETE FROM users WHERE port=$port AND user_key LIKE '$target_del:%';"
            systemctl restart sing-box; echo -e "${GREEN}Đã thực thi xóa.${NC}"; sleep 2 ;;
        0) exit 0 ;;
        *) ;;
    esac
    main_menu
}

if [ -f "$SCRIPT_PATH" ]; then main_menu; else check_and_update_system; fi
