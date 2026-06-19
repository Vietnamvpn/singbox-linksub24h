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
SCRIPT_PATH="/usr/local/bin/sbls"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Vietnamvpn/singbox-ls/refs/heads/main/install.sh"

set -e
trap 'catch_error $LINENO' ERR
catch_error() {
    echo -e "\n${RED} LỖI tại dòng $1. Quá trình cài đặt tạm dừng!${NC}"
    exit 1
}

get_ip() { echo $(curl -s ifconfig.me || curl -s icanhazip.com); }

# --- FORM NHẬP LIỆU THÔNG MINH THEO GIAO THỨC ---
prompt_node_config() {
    local proto=$1
    read -p " Nhập Cổng (Port) chính cho Node này: " RET_PORT </dev/tty
    
    read -p " Nhập Domain kết nối (Bỏ trống tự động dùng IP VPS): " RET_DOM </dev/tty
    if [ -z "$RET_DOM" ]; then RET_DOM=$(get_ip); fi
    
    RET_SNI=""
    RET_RANGE=""
    
    if [ "$proto" == "hysteria2" ]; then
        read -p " Nhập SNI chứng chỉ (Bỏ trống hệ thống lấy ngẫu nhiên): " RET_SNI </dev/tty
        read -p " Nhập Port Range (Ví dụ: 2345:2347) (Bỏ trống nếu không dùng): " RET_RANGE </dev/tty
    elif [ "$proto" == "tuic" ]; then
        read -p " Nhập SNI chứng chỉ (Bỏ trống hệ thống lấy ngẫu nhiên): " RET_SNI </dev/tty
    elif [ "$proto" == "vless" ]; then
        read -p " Nhập SNI giả lập Reality (Bắt buộc, bỏ trống mặc định www.microsoft.com): " RET_SNI </dev/tty
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
    
    echo -e "${YELLOW}--> Đang kiểm tra thông tin hệ điều hành...${NC}"
    if [ -f /etc/os-release ]; then 
        . /etc/os-release; OS_NAME=$NAME; OS_VER=$VERSION_ID
    else 
        echo -e "${RED} [LỖI] Không thể đọc thông tin hệ điều hành!${NC}"
        exit 1
    fi
    
    CPU_CORES=$(nproc)
    RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    
    echo -e "${YELLOW}--> Đang cập nhật danh sách gói (apt update)...${NC}"
    apt update -y &>/dev/null || echo -e "${RED} [CẢNH BÁO] Có lỗi nhỏ khi cập nhật apt, tiếp tục tiến trình...${NC}"
    
    echo -e "${YELLOW}--> Đang cài đặt các thư viện lõi (curl, jq, wget, ufw, openssl, sqlite3...)...${NC}"
    apt install -y curl jq wget ufw openssl sqlite3 tar git iptables &>/dev/null
    
    echo -e "${GREEN}--> Kiểm tra và chuẩn bị hệ thống hoàn tất!${NC}"
    sleep 1
    
    clear
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}    THÔNG TIN HỆ THỐNG VPS CỦA BẠN               ${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " Hệ điều hành : ${YELLOW}$OS_NAME $OS_VER${NC}"
    echo -e " Chip xử lý    : ${YELLOW}$CPU_CORES Cores CPU${NC}"
    echo -e " Dung lượng RAM: ${YELLOW}$RAM_TOTAL${NC}"
    echo -e " Ổ đĩa lưu trữ : ${YELLOW}Tổng $DISK_TOTAL (Còn trống $DISK_FREE)${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " 1. Đồng ý và tiếp tục cài đặt"
    echo -e " 0. Hủy bỏ"
    read -p "Lựa chọn của bạn (0-1): " init_choice </dev/tty
    if [ "$init_choice" != "1" ]; then 
        echo -e "${RED} Đã hủy cài đặt.${NC}"
        exit 0
    fi
    install_core
}

install_core() {
    echo -e "\n${BLUE}=================================================${NC}"
    echo -e "${BLUE}           BẮT ĐẦU CÀI ĐẶT SING-BOX              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    echo -e "${YELLOW}--> Đang tạo thư mục lưu trữ cấu hình...${NC}"
    mkdir -p $CONFIG_DIR
    
    echo -e "${YELLOW}--> Đang quét phiên bản Sing-box mới nhất từ Github...${NC}"
    # Đổi URL API sang repo của bạn
    TAG_NAME=$(curl -s https://api.github.com/repos/Vietnamvpn/sing-box/releases/latest | jq -r .tag_name)
    
    if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" == "null" ]; then
        echo -e "${RED} [LỖI] Không thể kết nối API Github repo của bạn!${NC}"
        exit 1
    fi
    VERSION=${TAG_NAME#v}
    echo -e "${GREEN}--> Tìm thấy phiên bản: ${TAG_NAME}${NC}"
    
    echo -e "${YELLOW}--> Đang tải xuống tệp cài đặt...${NC}"
    # Đổi URL download sang repo của bạn
    wget -qO sing-box.tar.gz "https://github.com/Vietnamvpn/sing-box/releases/download/${TAG_NAME}/sing-box-${VERSION}-linux-amd64.tar.gz"
    
    echo -e "${YELLOW}--> Đang giải nén và thiết lập quyền thực thi...${NC}"
    tar -xzf sing-box.tar.gz && mv sing-box-${VERSION}-linux-amd64/sing-box /usr/local/bin/
    rm -rf sing-box.tar.gz sing-box-* && chmod +x /usr/local/bin/sing-box
    echo -e "${GREEN}--> Cài đặt Sing-box Core thành công!${NC}"
    
    echo -e "${YELLOW}--> Đang khởi tạo tệp cấu hình (config.json)...${NC}"
    if [ ! -f $CONFIG_FILE ]; then
        cat << 'EOF' > $CONFIG_FILE
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
    fi

    echo -e "${YELLOW}--> Đang thiết lập cơ sở dữ liệu SQLite...${NC}"
    # Cấu trúc DB mới: Tích hợp thêm cột lưu Domain
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, node_type TEXT, port INTEGER, domain TEXT, user_key TEXT);"
    
    echo -e "${YELLOW}--> Đang tự động tạo chứng chỉ bảo mật (SSL)...${NC}"
    openssl req -x509 -nodes -newkey rsa:2048 -keyout $CONFIG_DIR/private.key -out $CONFIG_DIR/cert.pem -days 3650 -subj "/CN=bing.com" &>/dev/null

    echo -e "${YELLOW}--> Đang nạp Systemd Service để Sing-box chạy ngầm...${NC}"
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

    echo -e "${YELLOW}--> Đang khởi tạo dịch vụ Log Webhook (Chế độ Gom nhóm định kỳ)...${NC}"
    # Tạo file script forward log tối ưu gom cụm theo phút
    cat << 'EOF' > /usr/local/bin/log-forwarder.sh
#!/bin/bash
CONF_FILE="/usr/local/etc/sing-box/php_url.conf"
TEMP_LOG="/tmp/singbox_pending.log"

# Khởi tạo file tạm
touch "$TEMP_LOG"

# --- TIẾN TRÌNH 1: LẮNG NGHE VÀ HỨNG LOG VÀO FILE TẠM ---
# Chạy tiến trình này dưới dạng ngầm (background)
journalctl -u sing-box -f -n 0 | while read -r line; do
    # Nếu chưa cấu hình URL thì bỏ qua không ghi log để tránh đầy ổ cứng
    if [ ! -f "$CONF_FILE" ] || [ -z "$(cat "$CONF_FILE")" ]; then
        > "$TEMP_LOG" # Luôn làm trống file tạm nếu tắt tính năng
        continue
    fi
    
    # Lọc các log kết nối hợp lệ
    if [[ "$line" =~ "inbound/" && ( "$line" =~ "opened" || "$line" =~ "closed" || "$line" =~ "rejected" ) ]]; then
        echo "$line" >> "$TEMP_LOG"
    fi
done &
PID_JOURNAL=$!

# --- TIẾN TRÌNH 2: CỨ MỖI 60 GIÂY GOM LOG GỬI ĐI 1 LẦN ---
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)

# Đảm bảo tắt tiến trình hứng log khi dịch vụ stop
trap 'kill $PID_JOURNAL; exit 0' SIGTERM SIGINT

while true; do
    sleep 60 # Bạn có thể đổi thành 300 nếu muốn 5 phút gửi 1 lần
    
    # Kiểm tra cấu hình URL
    if [ ! -f "$CONF_FILE" ] || [ -z "$(cat "$CONF_FILE")" ]; then
        > "$TEMP_LOG"
        continue
    fi
    
    PHP_URL=$(cat "$CONF_FILE")
    
    # Nếu file tạm có dữ liệu (kích thước > 0)
    if [ -s "$TEMP_LOG" ]; then
        # Đổi tên file tạm thời để tránh xung đột dữ liệu khi đang ghi (Race Condition)
        mv "$TEMP_LOG" "${TEMP_LOG}.sending"
        touch "$TEMP_LOG"
        
        # Xử lý chuỗi dữ liệu: Xóa ký tự lạ, escape dấu nháy kép và chuyển dòng thành \n để đóng gói JSON hợp lệ
        LOG_CONTENT=$(cat "${TEMP_LOG}.sending" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
        
        # Gửi duy nhất 1 request HTTP POST chứa toàn bộ log của 1 phút qua
        curl -s -X POST "$PHP_URL" \
             -H "Content-Type: application/json" \
             -d "{\"vps_ip\":\"$VPS_IP\", \"batch\": true, \"log\":\"$LOG_CONTENT\"}"
             
        # Xóa file tạm đang gửi sau khi hoàn thành
        rm -f "${TEMP_LOG}.sending"
    fi
done
EOF
    chmod +x /usr/local/bin/log-forwarder.sh

    # Tạo service systemd cho log-forwarder (Giữ nguyên như cũ)
    cat << 'EOF' > /etc/systemd/system/log-forwarder.service
[Unit]
Description=Sing-box Log Forwarder (Batch Mode)
After=sing-box.service

[Service]
ExecStart=/usr/local/bin/log-forwarder.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable log-forwarder &>/dev/null
    systemctl start log-forwarder &>/dev/null
    
    echo -e "${YELLOW}--> Đang tải Menu Quản lý từ nguồn...${NC}"
    curl -sSL "$GITHUB_RAW_URL" -o $SCRIPT_PATH && chmod +x $SCRIPT_PATH
    
    echo -e "${GREEN}--> HOÀN TẤT THIẾT LẬP LÕI! Chuẩn bị chuyển sang cài đặt Node...${NC}"
    sleep 2
    
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
        echo -e "${GREEN} Đã lưu thành công.${NC}"
        read -p " Bạn có muốn thêm Node giao thức khác không? (y/n): " ext_choice </dev/tty
        if [[ "$ext_choice" != "y" && "$ext_choice" != "Y" ]]; then break; fi
    done
    
    clear
    echo -e "${PURPLE}========================================= ${NC}"
    echo -e "${PURPLE}   BƯỚC 2: KHỞI TẠO USER CHO TẤT CẢ NODE  ${NC}"
    echo -e "${PURPLE}========================================= ${NC}"
    read -p " Nhập tên Tài khoản (Username) chung: " common_name </dev/tty
    # Tự động tạo mật khẩu ngẫu nhiên 10 ký tự (gồm chữ và số)
    common_pass=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)
    echo -e " Mật khẩu (Password) chung tự động tạo: ${GREEN}$common_pass${NC}"
    common_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Xử lý làm sạch đầu vào để chống lỗi SQL Injection khi insert vào database
    safe_common_name=$(echo "$common_name" | sed "s/'/''/g")
    safe_common_pass=$(echo "$common_pass" | sed "s/'/''/g")
    
    for ((i=0; i<$node_idx; i++)); do
        type=${SESSION_TYPES[$i]}
        port=${SESSION_PORTS[$i]}
        dom=${SESSION_DOMAINS[$i]}
        sni=${SESSION_SNIS[$i]}
        
        # Làm sạch domain để đưa vào SQLite an toàn
        safe_dom=$(echo "$dom" | sed "s/'/''/g")
        
        if [ "$type" == "hysteria2" ]; then
            jq ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$common_name\", \"password\": \"$common_pass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            # Cập nhật DB: name::pass::
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $port, '$safe_dom', '$safe_common_name::$safe_common_pass::');"
            
        elif [ "$type" == "tuic" ]; then
            jq ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"password\": \"$common_pass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"], \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            # Cập nhật DB: name:uuid:pass::
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $port, '$safe_dom', '$safe_common_name:$common_uuid:$safe_common_pass::');"
            
        elif [ "$type" == "vless" ]; then
            /usr/local/bin/sing-box generate reality-keypair > /tmp/kp.txt 2>&1
            priv_key=$(awk '/[Pp]rivate/ {print $NF}' /tmp/kp.txt | tr -d '\r')
            pub_key=$(awk '/[Pp]ublic/ {print $NF}' /tmp/kp.txt | tr -d '\r')
            if [ -z "$priv_key" ]; then 
                priv_key="mK3_Ag3X_Placeholder_Must_Be_43_Chars_Long"
                pub_key="pub_placeholder"
            fi
            rm -f /tmp/kp.txt
            
            jq ".inbounds += [{\"type\": \"vless\", \"tag\": \"vless-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"name\": \"$common_name\"}], \"tls\": {\"enabled\": true, \"server_name\": \"$sni\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni\", \"server_port\": 443}, \"private_key\": \"$priv_key\", \"short_id\": [\"0123456789abcdef\"]}}, \"transport\": {\"type\": \"grpc\", \"service_name\": \"vless-grpc\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            # Cập nhật DB: name:uuid::pubkey:sni
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $port, '$safe_dom', '$safe_common_name:$common_uuid::$pub_key:$sni');"
        fi
    done
    systemctl restart sing-box; ufw reload &>/dev/null
    echo -e "\n${GREEN} ĐÃ THIẾT LẬP XONG TOÀN BỘ NODE! Nhấn Enter để vào Menu.${NC}"
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
    read -p " Nhập Username dành riêng cho Node mới này: " uname </dev/tty
    # Tự động tạo mật khẩu ngẫu nhiên 10 ký tự
    upass=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)
    echo -e " Mật khẩu (Password) tự động tạo cho Node này: ${GREEN}$upass${NC}"
    uuid_gen=$(cat /proc/sys/kernel/random/uuid)
    
    port=$RET_PORT
    dom=$RET_DOM
    sni=$RET_SNI
    range=$RET_RANGE
    
    # Làm sạch đầu vào để chống lỗi SQL Injection
    safe_uname=$(echo "$uname" | sed "s/'/''/g")
    safe_upass=$(echo "$upass" | sed "s/'/''/g")
    safe_dom=$(echo "$dom" | sed "s/'/''/g")
    
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
        jq ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$uname\", \"password\": \"$upass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        # Cập nhật DB: name::pass::
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $port, '$safe_dom', '$safe_uname::$safe_upass::');"
    elif [ "$proto" == "tuic" ]; then
        jq ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"], \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        # Cập nhật DB: name:uuid:pass::
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $port, '$safe_dom', '$safe_uname:$uuid_gen:$safe_upass::');"
    elif [ "$proto" == "vless" ]; then
        /usr/local/bin/sing-box generate reality-keypair > /tmp/kp.txt 2>/dev/null || true
        priv_key=$(awk '/[Pp]rivate/ {print $NF}' /tmp/kp.txt | tr -d '\r')
        pub_key=$(awk '/[Pp]ublic/ {print $NF}' /tmp/kp.txt | tr -d '\r')
        if [ -z "$priv_key" ]; then 
            priv_key="mK3_Ag3X_Placeholder_Must_Be_43_Chars_Long"
            pub_key="pub_placeholder"
        fi
        rm -f /tmp/kp.txt
        jq ".inbounds += [{\"type\": \"vless\", \"tag\": \"vless-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}], \"tls\": {\"enabled\": true, \"server_name\": \"$sni\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni\", \"server_port\": 443}, \"private_key\": \"$priv_key\", \"short_id\": [\"0123456789abcdef\"]}}, \"transport\": {\"type\": \"grpc\", \"service_name\": \"vless-grpc\"}}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        # Cập nhật DB: name:uuid::pubkey:sni
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $port, '$safe_dom', '$safe_uname:$uuid_gen::$pub_key:$sni');"
    fi
    
    systemctl restart sing-box
    echo -e "${GREEN} Thêm Node độc lập hoàn tất! Không ảnh hưởng tới các Node cũ.${NC}"
    sleep 3
}

# --- THÊM NGƯỜI DÙNG MỚI VÀO NODE ---
add_user_advanced() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}         THÊM NGƯỜI DÙNG MỚI VÀO NODE    ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    read -p " Nhập cổng Node muốn thêm, để trống sẽ thêm vào tất cả các Node: " target_port </dev/tty
    
    read -p " Nhập tên User viết liền không dấu: " uname </dev/tty
    if [ -z "$uname" ]; then
        echo -e "${RED} Lỗi: Tên User không được để trống! Thao tác bị hủy.${NC}"
        sleep 3
        return
    fi
    
    # Làm sạch tên user ngay từ đầu để dùng an toàn trong các câu lệnh SQL
    safe_uname=$(echo "$uname" | sed "s/'/''/g")

    # 1. KIỂM TRA TỒN TẠI ĐỂ TRÁNH TRÙNG LẶP TRÊN CÙNG 1 NODE
    if [ -z "$target_port" ]; then
        db_count=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users WHERE user_key LIKE '$safe_uname:%';")
        if [ "$db_count" -gt 0 ]; then
            echo -e "${YELLOW} Lỗi: Người dùng '$uname' ĐÃ TỒN TẠI! Không thể thêm đồng loạt để tránh trùng lặp.${NC}"
            sleep 3
            return
        fi
    else
        db_count=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users WHERE port=$target_port AND user_key LIKE '$safe_uname:%';")
        if [ "$db_count" -gt 0 ]; then
            echo -e "${YELLOW} Lỗi: Người dùng '$uname' ĐÃ CÓ MẶT ở Node cổng $target_port! Thao tác bị hủy.${NC}"
            sleep 3
            return
        fi
    fi

    # 2. ĐỒNG BỘ UUID & PASSWORD THEO CẤU TRÚC CHUẨN 5 TRƯỜNG
    # Lấy mật khẩu từ các node hỗ trợ mật khẩu (Hysteria2 hoặc TUIC) -> Trường số 3
    upass=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE user_key LIKE '$safe_uname:%' AND (node_type='hysteria2' OR node_type='tuic') LIMIT 1;" | cut -d':' -f3 | tr -d '\r')
    if [ -n "$upass" ]; then
        echo -e " Đã tìm thấy tên User cũ, tự động dùng lại Mật khẩu: ${GREEN}$upass${NC}"
    else
        # TỰ ĐỘNG TẠO MẬT KHẨU NGẪU NHIÊN 10 KÝ TỰ (Chữ cái và số)
        upass=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)
        echo -e " Đã tự động tạo Mật khẩu ngẫu nhiên: ${GREEN}$upass${NC}"
    fi
    
    safe_upass=$(echo "$upass" | sed "s/'/''/g")

    # Lấy UUID từ các node hỗ trợ UUID (VLESS hoặc TUIC) -> Trường số 2
    uuid_gen=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE user_key LIKE '$safe_uname:%' AND (node_type='vless' OR node_type='tuic') LIMIT 1;" | cut -d':' -f2 | tr -d '\r')
    if [ -n "$uuid_gen" ]; then
        echo -e " Đã tìm thấy tên User cũ, tự động đồng bộ UUID: ${GREEN}$uuid_gen${NC}"
    else
        uuid_gen=$(cat /proc/sys/kernel/random/uuid)
    fi
    
    set +e 
    
    if [ -z "$target_port" ]; then
        ports=$(jq -r '.inbounds[].listen_port' $CONFIG_FILE)
        success_count=0
        
        for p in $ports; do
            type=$(jq -r ".inbounds[] | select(.listen_port == $p) | .type" $CONFIG_FILE)
            dom=$(sqlite3 $DB_FILE "SELECT domain FROM users WHERE port=$p LIMIT 1;")
            if [ -z "$dom" ]; then dom=$(get_ip); fi
            safe_dom=$(echo "$dom" | sed "s/'/''/g")
            
            if [ "$type" == "hysteria2" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $p, '$safe_dom', '$safe_uname::$safe_upass::');"
                success_count=$((success_count + 1))
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $p, '$safe_dom', '$safe_uname:$uuid_gen:$safe_upass::');"
                success_count=$((success_count + 1))
            elif [ "$type" == "vless" ]; then
                sni=$(jq -r ".inbounds[] | select(.listen_port == $p).tls.server_name" $CONFIG_FILE)
                safe_sni=$(echo "$sni" | sed "s/'/''/g")
                # Lấy Public Key của node VLESS này (Trường số 4)
                pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$p AND node_type='vless' LIMIT 1;" | cut -d':' -f4 | tr -d '\r')
                if [ -z "$pub_k" ]; then pub_k="reused_key"; fi
                
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $p, '$safe_dom', '$safe_uname:$uuid_gen::$pub_k:$safe_sni');"
                success_count=$((success_count + 1))
            fi
        done
        
        if [ "$success_count" -gt 0 ]; then
            echo -e "${GREEN} Đã thêm User [${uname}] vào $success_count Node thành công!${NC}"
        else
            echo -e "${RED} Lỗi cấu hình JSON, không thêm được Node nào!${NC}"
        fi
    else
        type=$(jq -r ".inbounds[] | select(.listen_port == $target_port) | .type" $CONFIG_FILE)
        
        if [ -z "$type" ] || [ "$type" == "null" ]; then
            echo -e "${RED} Lỗi: Cổng $target_port không tồn tại trong cấu hình!${NC}"
        else
            dom=$(sqlite3 $DB_FILE "SELECT domain FROM users WHERE port=$target_port LIMIT 1;")
            if [ -z "$dom" ]; then dom=$(get_ip); fi
            safe_dom=$(echo "$dom" | sed "s/'/''/g")
            
            if [ "$type" == "hysteria2" ]; then
                jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('hysteria2', $target_port, '$safe_dom', '$safe_uname::$safe_upass::');"
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('tuic', $target_port, '$safe_dom', '$safe_uname:$uuid_gen:$safe_upass::');"
            elif [ "$type" == "vless" ]; then
                sni=$(jq -r ".inbounds[] | select(.listen_port == $target_port).tls.server_name" $CONFIG_FILE)
                safe_sni=$(echo "$sni" | sed "s/'/''/g")
                pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$target_port AND node_type='vless' LIMIT 1;" | cut -d':' -f4 | tr -d '\r')
                if [ -z "$pub_k" ]; then pub_k="reused_key"; fi
                
                jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, domain, user_key) VALUES ('vless', $target_port, '$safe_dom', '$safe_uname:$uuid_gen::$pub_k:$safe_sni');"
            fi
            echo -e "${GREEN} Đã thêm User [${uname}] vào cổng [$target_port] thành công!${NC}"
        fi
    fi
    
    set -e 
    systemctl restart sing-box; sleep 3
}

# --- HÀM GỠ CÀI ĐẶT TOÀN BỘ ---
uninstall_system() {
    clear
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}   CẢNH BÁO: GỠ CÀI ĐẶT VÀ XÓA TÀN DƯ    ${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e " Thao tác này sẽ xóa KHÔNG THỂ KHÔI PHỤC:"
    echo -e " - Toàn bộ cấu hình Node và Database người dùng."
    echo -e " - File thực thi Core Sing-box."
    echo -e " - Dịch vụ (Service) chạy ngầm của hệ thống."
    echo -e " - Xóa cả script menu tool này."
    echo -e "----------------------------------------"
    read -p "Bạn có CHẮC CHẮN muốn dọn sạch mọi thứ không? (y/n): " confirm </dev/tty
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    set +e
        echo -e "\n${YELLOW}--> Đang dừng và gỡ bỏ Service...${NC}"
        systemctl stop sing-box log-forwarder &>/dev/null
        systemctl disable sing-box log-forwarder &>/dev/null
        rm -f /etc/systemd/system/sing-box.service
        rm -f /etc/systemd/system/log-forwarder.service
        systemctl daemon-reload
        
        echo -e "${YELLOW}--> Đang xóa Core, Tools và File cấu hình...${NC}"
        rm -f /usr/local/bin/sing-box
        rm -f /usr/local/bin/log-forwarder.sh
        rm -rf /usr/local/etc/sing-box
        
        echo -e "${YELLOW}--> Đang dọn dẹp Iptables Port Range (nếu có)...${NC}"
        if [ -f /etc/rc.local ]; then
            sed -i '/iptables -t nat -A PREROUTING -p udp --dport/d' /etc/rc.local 2>/dev/null
        fi
        
        echo -e "${YELLOW}--> Đang xóa Tool Menu...${NC}"
        rm -f /usr/local/bin/box-tool
        
        echo -e "${GREEN} Đã dọn sạch toàn bộ tàn dư của Sing-box trên VPS!${NC}"
        echo -e "Script sẽ tự động thoát."
        rm -f $0 # Tự xóa chính file script đang chạy
        exit 0
    else
        echo -e "${GREEN}Đã hủy thao tác gỡ cài đặt.${NC}"
        sleep 3
    fi
}

# --- HÀM CẬP NHẬT MÃ NGUỒN ---
update_script() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}       CẬP NHẬT MÃ NGUỒN TỪ GITHUB       ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "--> Đang tải file cập nhật mới nhất..."
    
    # Tải script mới vào file tạm
    curl -sSL "$GITHUB_RAW_URL" -o /tmp/box-tool-update.sh
    
    # Kiểm tra xem tải có thành công và file có dữ liệu không
    if [ $? -eq 0 ] && [ -s /tmp/box-tool-update.sh ]; then
        mv /tmp/box-tool-update.sh $SCRIPT_PATH
        chmod +x $SCRIPT_PATH
        echo -e "${GREEN} Đã cập nhật Tool thành công!${NC}"
        echo -e "--> Đang khởi động lại giao diện mới..."
        sleep 3
        # Tự động thay thế tiến trình hiện tại bằng script mới
        exec $SCRIPT_PATH
    else
        echo -e "${RED} Cập nhật thất bại! Không thể tải file từ Github.${NC}"
        echo -e "Vui lòng kiểm tra lại mạng hoặc link Github."
        rm -f /tmp/box-tool-update.sh
        sleep 3
    fi
}

# --- TÍNH NĂNG MỚI: XEM TRẠNG THÁI VPS ---
view_vps_status() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}           TRẠNG THÁI HỆ THỐNG VPS       ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e " Thời gian hoạt động (Uptime): $(uptime -p)"
    echo -e " Mức tải hệ thống (Load Avg) : $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "----------------------------------------"
    echo -e " Sử dụng Bộ nhớ (RAM):"
    free -h
    echo -e "----------------------------------------"
    echo -e " Tình trạng Ổ đĩa (Disk Space):"
    df -h /
    echo -e "----------------------------------------"
    echo -e " Trạng thái kết nối mạng (Port đang mở):"
    ss -tuln | grep -E 'Listen|ESTAB' | head -n 15
    echo -e "----------------------------------------"
    read -p "Nhấn Enter để quay lại..." dummy </dev/tty
}

# --- TÍNH NĂNG MỚI: TẠO BỘ NHỚ ẢO (SWAP) ---
create_swap() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}         CẤU HÌNH BỘ NHỚ ẢO (SWAP)        ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e " Trạng thái SWAP hiện tại hệ thống:"
    swapon --show
    echo -e "----------------------------------------"
    read -p " Nhập dung lượng SWAP muốn tạo (Ví dụ: 1 hoặc 2 tương ứng 1GB/2GB, hoặc 0 để hủy): " swap_size </dev/tty
    if [ "$swap_size" == "0" ] || [ -z "$swap_size" ]; then
        echo -e "${YELLOW} Đã hủy thao tác cấu hình SWAP.${NC}"
        sleep 2
        return
    fi
    
    echo -e "--> Đang khởi tạo tệp bộ nhớ ảo SWAP ${swap_size}GB (Vui lòng chờ)..."
    swapoff -a &>/dev/null
    rm -f /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count=$((swap_size * 1024)) status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi
    echo -e "${GREEN} Tạo dung lượng ảo SWAP ${swap_size}GB thành công!${NC}"
    sleep 3
}

# --- CẬP NHẬT CẤU HÌNH NODE PROXY (ĐÃ THÊM HỦY, ĐỔI TAG VÀ ĐỔI SNI) ---
update_node_config() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}     CẬP NHẬT CẤU HÌNH NODE PROXY        ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e " ${YELLOW}(Bạn có thể nhập 0 hoặc n để hủy bỏ và quay lại Menu)${NC}"
    echo -e "----------------------------------------"
    
    read -p " Nhập cổng (Port) hiện tại của Node cần sửa: " old_port </dev/tty
    if [ -z "$old_port" ] || [ "$old_port" == "0" ] || [ "$old_port" == "n" ] || [ "$old_port" == "N" ]; then
        echo -e "${YELLOW} Đã hủy thao tác cập nhật Node.${NC}"
        sleep 2
        return
    fi
    
    # Kiểm tra tính hợp lệ của cổng đầu vào tránh lỗi cú pháp lệnh jq
    if [[ ! "$old_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED} Lỗi: Cổng phải là một số nguyên hợp lệ!${NC}"
        sleep 3
        return
    fi

    node_exists=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .listen_port" $CONFIG_FILE 2>/dev/null)
    if [ -z "$node_exists" ] || [ "$node_exists" == "null" ]; then
        echo -e "${RED} Lỗi: Không tìm thấy Node nào đang chạy ở cổng $old_port!${NC}"
        sleep 3
        return
    fi
    
    # Lấy thông tin Tag hiện tại hiển thị để người dùng dễ theo dõi
    current_tag=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .tag" $CONFIG_FILE 2>/dev/null)
    current_sni=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .tls.server_name" $CONFIG_FILE 2>/dev/null)
    
    echo -e " Node đang chọn có Tag hiện tại là: ${GREEN}$current_tag${NC}"
    echo -e " SNI hiện tại đang sử dụng là: ${GREEN}$current_sni${NC}"
    echo -e "----------------------------------------"
    echo " 1. Đổi Cổng (Port) mới cho Node này"
    echo " 2. Đổi Domain/IP kết nối mới cho Node này"
    echo " 3. Đổi Tên nhận diện (Tag) mới cho Node này"
    echo " 4. Đổi SNI (server_name) mới cho Node này"
    read -p " Chọn mục cần cập nhật (1-4): " update_choice </dev/tty
    
    if [ -z "$update_choice" ] || [ "$update_choice" == "0" ] || [ "$update_choice" == "n" ] || [ "$update_choice" == "N" ]; then
        echo -e "${YELLOW} Đã hủy thao tác cập nhật Node.${NC}"
        sleep 2
        return
    fi
    
    if [ "$update_choice" == "1" ]; then
        read -p " Nhập Cổng (Port) MỚI muốn thay đổi: " new_port </dev/tty
        if [ -z "$new_port" ] || [ "$new_port" == "0" ] || [ "$new_port" == "n" ] || [ "$new_port" == "N" ]; then
            echo -e "${YELLOW} Đã hủy thao tác.${NC}"
            sleep 2
            return
        fi
        
        if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
            echo -e "${RED} Lỗi: Cổng phải là một số nguyên hợp lệ!${NC}"
            sleep 3
            return
        fi
        
        port_check=$(jq -r ".inbounds[] | select(.listen_port == $new_port) | .listen_port" $CONFIG_FILE 2>/dev/null)
        if [ -n "$port_check" ] && [ "$port_check" != "null" ]; then
            echo -e "${RED} Lỗi: Cổng MỚI $new_port đã bị chiếm dụng bởi Node khác!${NC}"
            sleep 3
            return
        fi
        
        echo -e "--> Đang cập nhật cổng và định dạng lại tag tự động trong file cấu hình json..."
        node_type=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .type" $CONFIG_FILE)
        new_tag="${node_type}-$new_port"
        jq "(.inbounds[] | select(.listen_port == $old_port)) |= (.listen_port = $new_port | .tag = \"$new_tag\")" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        
        echo -e "--> Đang đồng bộ hóa Database..."
        sqlite3 $DB_FILE "UPDATE users SET port=$new_port WHERE port=$old_port;"
        
        echo -e "--> Đang cập nhật lại quy tắc Tường lửa UFW..."
        ufw allow $new_port/tcp &>/dev/null
        ufw allow $new_port/udp &>/dev/null
        ufw delete allow $old_port/tcp &>/dev/null
        ufw delete allow $old_port/udp &>/dev/null
        ufw reload &>/dev/null
        
        systemctl restart sing-box
        echo -e "${GREEN} Cập nhật chuyển đổi cổng từ $old_port sang $new_port thành công!${NC}"
        sleep 3
        
    elif [ "$update_choice" == "2" ]; then
        read -p " Nhập Domain hoặc IP kết nối MỚI: " new_dom </dev/tty
        if [ -z "$new_dom" ] || [ "$new_dom" == "0" ] || [ "$new_dom" == "n" ] || [ "$new_dom" == "N" ]; then
            echo -e "${YELLOW} Đã hủy thao tác.${NC}"
            sleep 2
            return
        fi
        
        # Làm sạch Domain trước khi lưu vào DB
        safe_new_dom=$(echo "$new_dom" | sed "s/'/''/g")
        
        echo -e "--> Đang cập nhật thông tin Domain mới vào hệ thống Database..."
        sqlite3 $DB_FILE "UPDATE users SET domain='$safe_new_dom' WHERE port=$old_port;"
        
        echo -e "${GREEN} Cập nhật Domain kết nối cho Node cổng $old_port thành công!${NC}"
        sleep 3
        
    elif [ "$update_choice" == "3" ]; then
        read -p " Nhập Tên nhận diện (Tag) MỚI cho Node này: " new_tag </dev/tty
        if [ -z "$new_tag" ] || [ "$new_tag" == "0" ] || [ "$new_tag" == "n" ] || [ "$new_tag" == "N" ]; then
            echo -e "${YELLOW} Đã hủy thao tác.${NC}"
            sleep 2
            return
        fi
        
        # Làm sạch Tag (chống nhập nháy kép làm gãy lệnh jq)
        safe_new_tag=$(echo "$new_tag" | sed 's/"/\\"/g')
        
        # Kiểm tra chống trùng lặp tên Tag trong tệp cấu hình JSON
        tag_check=$(jq -r ".inbounds[] | select(.tag == \"$safe_new_tag\") | .tag" $CONFIG_FILE 2>/dev/null)
        if [ -n "$tag_check" ] && [ "$tag_check" != "null" ]; then
            echo -e "${RED} Lỗi: Tên Tag MỚI [$new_tag] đã tồn tại ở một Node khác!${NC}"
            sleep 3
            return
        fi
        
        echo -e "--> Đang cập nhật cấu trúc tên Tag trong file cấu hình json..."
        jq "(.inbounds[] | select(.listen_port == $old_port)).tag = \"$safe_new_tag\"" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        
        systemctl restart sing-box
        echo -e "${GREEN} Cập nhật Tên Tag cho Node cổng $old_port thành [$new_tag] thành công!${NC}"
        sleep 3
        
    elif [ "$update_choice" == "4" ]; then
        read -p " Nhập SNI (server_name) MỚI cho Node này: " new_sni </dev/tty
        if [ -z "$new_sni" ] || [ "$new_sni" == "0" ] || [ "$new_sni" == "n" ] || [ "$new_sni" == "N" ]; then
            echo -e "${YELLOW} Đã hủy thao tác.${NC}"
            sleep 2
            return
        fi
        
        safe_new_sni=$(echo "$new_sni" | sed 's/"/\\"/g')
        node_type=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .type" $CONFIG_FILE)
        
        echo -e "--> Đang cập nhật cấu hình SNI..."
        if [ "$node_type" == "vless" ]; then
            # VLESS cần đổi cả server_name và reality.handshake.server
            jq "(.inbounds[] | select(.listen_port == $old_port)).tls.server_name = \"$safe_new_sni\" | (.inbounds[] | select(.listen_port == $old_port)).tls.reality.handshake.server = \"$safe_new_sni\"" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            
            # Đồng bộ lại SNI vào cơ sở dữ liệu để Link VLESS khi xuất ra menu 1 được chính xác
            sqlite3 $DB_FILE "SELECT id, user_key FROM users WHERE port=$old_port AND node_type='vless';" | while read -r row; do
                u_id=$(echo "$row" | cut -d'|' -f1)
                u_key=$(echo "$row" | cut -d'|' -f2)
                # Lấy 4 trường đầu của VLESS (name:uuid:pass:pub_k) và gắn SNI mới vào cuối
                part1_4=$(echo "$u_key" | cut -d':' -f1-4)
                sqlite3 $DB_FILE "UPDATE users SET user_key='${part1_4}:${safe_new_sni}' WHERE id=$u_id;"
            done
        else
            # Hysteria2 và TUIC chỉ cần đổi tls.server_name
            jq "(.inbounds[] | select(.listen_port == $old_port)).tls.server_name = \"$safe_new_sni\"" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        fi
        
        systemctl restart sing-box
        echo -e "${GREEN} Cập nhật SNI cho Node cổng $old_port thành [$new_sni] thành công!${NC}"
        sleep 3
        
    else
        echo -e "${RED} Lựa chọn sai định dạng!${NC}"
        sleep 2
    fi
}

# --- TÍNH NĂNG MỚI: XIN CHỨNG CHỈ SSL CLOUDFLARE ---
issue_cloudflare_cert() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   XIN CHỨNG CHỈ WILDCARD SSL CLOUDFLARE ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "Giải pháp: Xin chứng chỉ dạng *.tenmien.com để TẤT CẢ các node"
    echo -e "subdomain (us1, us2, us3...) dùng chung một lần duy nhất."
    echo -e "Yêu cầu: Tên miền quản lý bởi Cloudflare và bạn có Global API Key."
    echo -e " ${YELLOW}(Bạn có thể nhập 0 hoặc n để hủy bỏ và quay lại Menu)${NC}"
    echo -e "----------------------------------------"
    
    read -p " Nhập Tên miền gốc hoặc Wildcard (Ví dụ: nodeserver.ccwu.cc): " cf_domain </dev/tty
    if [ -z "$cf_domain" ] || [ "$cf_domain" == "0" ] || [ "$cf_domain" == "n" ] || [ "$cf_domain" == "N" ]; then
        echo -e "${YELLOW} Đã hủy thao tác xin chứng chỉ SSL.${NC}"
        sleep 2
        return
    fi
    
    # Tự động định dạng lại thành cấu trúc Wildcard *. nếu người dùng chỉ nhập tên miền gốc
    if [[ "$cf_domain" != \*.* ]]; then
        echo -e "${YELLOW}--> Tự động chuyển đổi tên miền thành định dạng Wildcard: *.$cf_domain${NC}"
        cf_domain="*.$cf_domain"
        sleep 1
    fi
    
    read -p " Nhập Email tài khoản Cloudflare của bạn: " cf_email </dev/tty
    if [ "$cf_email" == "0" ] || [ "$cf_email" == "n" ] || [ "$cf_email" == "N" ]; then
        echo -e "${YELLOW} Đã hủy thao tác xin chứng chỉ SSL.${NC}"
        sleep 2
        return
    fi
    
    read -p " Nhập Global API Key của Cloudflare: " cf_key </dev/tty
    if [ "$cf_key" == "0" ] || [ "$cf_key" == "n" ] || [ "$cf_key" == "N" ]; then
        echo -e "${YELLOW} Đã hủy thao tác xin chứng chỉ SSL.${NC}"
        sleep 2
        return
    fi
    
    if [ -z "$cf_email" ] || [ -z "$cf_key" ]; then
        echo -e "${RED} Lỗi: Email và Global API Key không được để trống!${NC}"
        sleep 3
        return
    fi
    
    echo -e "--> Đang thiết lập công cụ acme.sh..."
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        curl https://get.acme.sh | sh -s email=$cf_email &>/dev/null
    fi
    
    export CF_Key="$cf_key"
    export CF_Email="$cf_email"
    
    echo -e "--> Đang tiến hành xác thực DNS API và xin chứng chỉ Wildcard từ Cloudflare..."
    ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$cf_domain" --keylength ec-256 --force
    
    if [ $? -eq 0 ]; then
        echo -e "--> Đang xuất chứng chỉ vào thư mục lưu trữ lõi..."
        # Ghi đè chứng chỉ Wildcard mới vào 2 file dùng chung duy nhất của hệ thống
        ~/.acme.sh/acme.sh --install-cert -d "$cf_domain" --ecc \
            --key-file "$CONFIG_DIR/private.key" \
            --fullchain-file "$CONFIG_DIR/cert.pem"
            
        echo -e "--> Đang áp dụng cấu hình và khởi động lại Sing-box..."
        
        # BẢO VỆ DỮ LIỆU: Hoàn toàn KHÔNG sửa đổi file config.json hay Database.
        # Từng node (us1, us2...) giữ nguyên tên miền gốc của nó để xuất link chuẩn xác.
        systemctl restart sing-box
        
        echo -e "${GREEN} Xin thành công chứng chỉ Wildcard [$cf_domain]!${NC}"
        echo -e "${GREEN} Toàn bộ các node con (us1, us2, us3...) đã tự động được bảo mật thành công!${NC}"
    else
        echo -e "${RED} Xin cấp chứng chỉ thất bại! Vui lòng kiểm tra lại thông tin API hoặc trạng thái DNS.${NC}"
    fi
    sleep 5
}

# --- TÍNH NĂNG MỚI: TẠM KHÓA / MỞ KHÓA USER ---
toggle_user_status() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}      TẠM KHÓA / MỞ KHÓA MẠNG NGƯỜI DÙNG ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    read -p " Nhập chính xác Tên User cần xử lý: " target_user </dev/tty
    
    if [ -z "$target_user" ]; then
        echo -e "${RED} Tên User không được để trống!${NC}"; sleep 2; return
    fi

    # Kiểm tra xem User có tồn tại trong DB không
    db_check=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users WHERE user_key LIKE '$target_user:%';")
    if [ "$db_check" -eq 0 ]; then
        echo -e "${RED} Lỗi: Không tìm thấy người dùng [$target_user] trong Database!${NC}"; sleep 3; return
    fi

    # Lấy UUID của user (dành cho VLESS/TUIC)
    target_uuid=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE user_key LIKE '$target_user:%' AND node_type IN ('tuic', 'vless') LIMIT 1;" | cut -d':' -f2 | tr -d '\r')
    if [ -z "$target_uuid" ]; then target_uuid="NO_UUID_FOUND"; fi

    # Kiểm tra xem user có đang nằm trong config.json (đang có mạng) không
    is_active=$(jq "[.inbounds[] | select(has(\"users\")).users[]? | select((.name // \"\") == \"$target_user\" or (.uuid // \"\") == \"$target_uuid\")] | length" $CONFIG_FILE)

    if [ "$is_active" -gt 0 ]; then
        # === TRƯỜNG HỢP 1: ĐANG CÓ MẠNG -> TIẾN HÀNH KHÓA (CẮT MẠNG) ===
        echo -e "--> Đang tiến hành ${RED}TẠM KHÓA${NC} mạng của [$target_user]..."
        
        # Chỉ xóa khỏi config.json, GIỮ NGUYÊN trong SQLite DB
        jq "(.inbounds[] | select(has(\"users\")).users) |= map(select((.name // \"\") != \"$target_user\" and (.uuid // \"\") != \"$target_uuid\"))" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
        
        systemctl restart sing-box
        echo -e "${GREEN} Đã cắt mạng User [$target_user] thành công! (Dữ liệu vẫn được bảo lưu)${NC}"
        sleep 3
    else
        # === TRƯỜNG HỢP 2: ĐANG BỊ KHÓA -> TIẾN HÀNH MỞ LẠI MẠNG ===
        echo -e "--> Đang tiến hành ${GREEN}MỞ LẠI${NC} mạng cho [$target_user]..."
        
        # Đọc dữ liệu gốc từ DB và khôi phục vào config.json
        sqlite3 $DB_FILE "SELECT node_type, port, user_key FROM users WHERE user_key LIKE '$target_user:%';" | while read -r row; do
            ntype=$(echo "$row" | cut -d'|' -f1)
            port=$(echo "$row" | cut -d'|' -f2)
            ukey=$(echo "$row" | cut -d'|' -f3)
            
            uuid=$(echo "$ukey" | cut -d':' -f2)
            upass=$(echo "$ukey" | cut -d':' -f3)
            
            if [ "$ntype" == "hysteria2" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) += [{\"name\": \"$target_user\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            elif [ "$ntype" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) += [{\"uuid\": \"$uuid\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            elif [ "$ntype" == "vless" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) += [{\"uuid\": \"$uuid\", \"name\": \"$target_user\"}]" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            fi
        done
        
        systemctl restart sing-box
        echo -e "${GREEN} Đã khôi phục mạng cho User [$target_user] thành công!${NC}"
        sleep 3
    fi
}

# --- TÍNH NĂNG MỚI: CẤU HÌNH WEBHOOK PHP ---
config_webhook() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    CẤU HÌNH GỬI LOG LÊN WEB (WEBHOOK)   ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    CONF_FILE="/usr/local/etc/sing-box/php_url.conf"
    
    if [ -f "$CONF_FILE" ] && [ -n "$(cat "$CONF_FILE")" ]; then
        current_url=$(cat "$CONF_FILE")
        echo -e " URL hiện tại: ${GREEN}$current_url${NC}"
        echo -e " Trạng thái: ${GREEN}Đang hoạt động${NC}"
    else
        echo -e " Trạng thái: ${YELLOW}Chưa cấu hình (Đang tắt)${NC}"
    fi
    echo -e "----------------------------------------"
    echo -e " 1. Thêm / Thay đổi URL PHP nhận Log"
    echo -e " 2. Xóa URL (Tắt tính năng gửi Log)"
    echo -e " 0. Quay lại Menu"
    read -p " Nhập lựa chọn (0-2): " wh_choice </dev/tty
    
    case $wh_choice in
        1)
            read -p " Nhập URL trang PHP (Bắt đầu bằng http:// hoặc https://): " new_url </dev/tty
            if [[ "$new_url" == http* ]]; then
                echo "$new_url" > "$CONF_FILE"
                systemctl restart log-forwarder
                echo -e "${GREEN} Cập nhật thành công! Mọi log mới từ bây giờ sẽ được gửi lên web.${NC}"
            else
                echo -e "${RED} Lỗi: URL phải bắt đầu bằng http:// hoặc https://${NC}"
            fi
            sleep 3
            ;;
        2)
            rm -f "$CONF_FILE"
            systemctl restart log-forwarder
            echo -e "${GREEN} Đã xóa URL. Tính năng gửi log đã được tắt!${NC}"
            sleep 3
            ;;
        0) return ;;
        *) echo -e "${RED} Lựa chọn không hợp lệ!${NC}"; sleep 1 ;;
    esac
}

main_menu() {
    clear
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${BLUE}                       MENU QUẢN LÝ SING-BOX PROXY TOOL V3                     ${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e " 1. Xem danh sách & Xuất Link kết nối User | 10. Xin chứng chỉ SSL Cloudflare"
    echo -e " 2. Xem LOG theo dõi kết nối trực tiếp     | 11. Bắt đầu Sing-box"
    echo -e " 3. Xem trạng thái hệ thống VPS            | 12. Dừng Sing-box"
    echo -e "-------------------------------------------------------------------------------"
    echo -e " 4. Thêm một Node độc lập mới              | 13. Khởi động lại"
    echo -e " 5. Xóa bỏ một Node (Đóng cổng)            | 14. Gỡ cài đặt, Xóa sạch tàn dư"
    echo -e " 6. Cập nhật Đổi cổng hoặc Domain cho Node | 15. Cập nhật Tool (Từ Github)"
    echo -e "-------------------------------------------------------------------------------"
    echo -e " 7. Thêm người dùng                        | 16. Tạm khóa / Mở khóa mạng User"
    echo -e " 8. Xóa bỏ người dùng khỏi Node            | 17. Cấu hình Webhook"
    echo -e " 9. Tạo bộ nhớ ảo (SWAP)                   |  0. Thoát hệ thống"
    echo -e "${BLUE}===============================================================================${NC}"
    
    # Lấy trạng thái hiện tại của Sing-box để hiển thị
    if systemctl is-active --quiet sing-box; then
        echo -e "Trạng thái: ${GREEN}Đang chạy (Active)${NC}"
    else
        echo -e "Trạng thái: ${RED}Đã dừng (Inactive)${NC}"
    fi
    echo -e "-------------------------------------------------------------------------------"
    
    read -p "Nhập lựa chọn: " m_choice </dev/tty
    
    case $m_choice in
        1)
            clear
            echo "======================================================="
            echo "          DANH SÁCH TOÀN BỘ LINK NODE CỦA BẠN          "
            echo "======================================================="
            
            # --- TỰ ĐỘNG LẤY TÊN QUỐC GIA CỦA VPS ---
            echo -e "--> Đang lấy thông tin quốc gia của máy chủ..."
            # Dùng API để lấy tên quốc gia, nếu lỗi sẽ để mặc định là "VPS"
            vps_country=$(curl -s -m 5 http://ip-api.com/json/ | jq -r '.country // "VPS"')
            
            # Chuyển đổi tên để tránh lỗi dấu cách trong Link URL (VD: Hong Kong -> Hong_Kong)
            safe_country=$(echo "$vps_country" | sed 's/ /_/g')
            
            # Lấy danh sách Username duy nhất từ cấu trúc "username:..." trong Database
            all_names=$(sqlite3 $DB_FILE "SELECT DISTINCT SUBSTR(user_key, 1, INSTR(user_key, ':') - 1) FROM users;")
            
            if [ -z "$all_names" ]; then
                echo -e "\n ${YELLOW}Chưa có người dùng nào trên hệ thống.${NC}"
            else
                for u_name in $all_names; do
                    echo -e "\n NGƯỜI DÙNG: $u_name"
                    echo "-------------------------------------------------------"
                    
                    # Khởi tạo biến đếm để làm số thứ tự 01, 02...
                    node_count=1
                    
                    # Quét toàn bộ Node mà user này sở hữu
                    sqlite3 $DB_FILE "SELECT node_type, port, domain, user_key FROM users WHERE user_key LIKE '$u_name:%';" | while read -r row; do
                        ntype=$(echo "$row" | cut -d'|' -f1)
                        port=$(echo "$row" | cut -d'|' -f2)
                        dom=$(echo "$row" | cut -d'|' -f3)
                        ukey=$(echo "$row" | cut -d'|' -f4)
                        
                        # Tách dữ liệu từ cấu trúc 5 trường (username:uuid:password:public_key:sni)
                        uuid=$(echo "$ukey" | cut -d':' -f2)
                        upass=$(echo "$ukey" | cut -d':' -f3)
                        pub_k=$(echo "$ukey" | cut -d':' -f4)
                        db_sni=$(echo "$ukey" | cut -d':' -f5)
                        
                        # Nếu Database không lưu SNI, quét nhanh từ config.json
                        if [ -z "$db_sni" ]; then
                            sni=$(jq -r ".inbounds[] | select(.listen_port == $port) | .tls.server_name // \"bing.com\"" $CONFIG_FILE 2>/dev/null)
                        else
                            sni=$db_sni
                        fi
                        
                        # --- TẠO TÊN TAG GỌN GÀNG: Hong_Kong-01 ---
                        idx_str=$(printf "%02d" $node_count)
                        remark_tag="${safe_country}-${idx_str}"
                        
                        # Xuất Link với Remark Tag mới
                        if [ "$ntype" == "hysteria2" ]; then
                            echo " hysteria2://$upass@$dom:$port?insecure=1&sni=$sni#$remark_tag"
                        elif [ "$ntype" == "tuic" ]; then
                            echo " tuic://$uuid:$upass@$dom:$port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=1#$remark_tag"
                        elif [ "$ntype" == "vless" ]; then
                            echo " vless://$uuid@$dom:$port?security=reality&encryption=none&pbk=$pub_k&headerType=none&fp=chrome&spx=%2F&type=grpc&sni=$sni&serviceName=vless-grpc&sid=0123456789abcdef#$remark_tag"
                        fi
                        
                        # Tăng số thứ tự cho Node tiếp theo
                        node_count=$((node_count + 1))
                    done
                done
            fi
            
            echo -e "\n======================================================="
            read -p "Nhấn Enter để quay lại..." dummy </dev/tty ;;
        2) journalctl -u sing-box --no-hostname -n 50 -f ;;
        3) view_vps_status ;;
        4) add_single_node_menu ;;
        5)
            read -p "Nhập số Cổng (Port) của node muốn xóa: " del_port </dev/tty
            jq "del(.inbounds[] | select(.listen_port == $del_port))" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
            ufw delete allow $del_port/udp &>/dev/null; sqlite3 $DB_FILE "DELETE FROM users WHERE port=$del_port;"
            systemctl restart sing-box; echo -e "${GREEN}--> Đã dọn sạch cổng $del_port!${NC}"; sleep 3 ;;
        6) update_node_config ;;
        7) add_user_advanced ;;
        8)
            clear
            echo -e "${BLUE}=========================================${NC}"
            echo -e "${BLUE}         XÓA NGƯỜI DÙNG KHỎI NODE        ${NC}"
            echo -e "${BLUE}=========================================${NC}"
            read -p " Nhập chính xác Tên User cần xóa: " target_del </dev/tty
            
            if [ -z "$target_del" ]; then
                echo -e "${RED} Tên User không được để trống!${NC}"
                sleep 3
            else
                # Kiểm tra trước xem user này có tồn tại trong hệ thống không
                db_check=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users WHERE user_key LIKE '$target_del:%';")
                if [ "$db_check" -eq 0 ]; then
                    echo -e "${RED} Lỗi: Không tìm thấy người dùng [$target_del] trong hệ thống Database!${NC}"
                    sleep 3
                else
                    read -p " Nhập Cổng muốn xóa, để trống sẽ xóa tất cả: " port </dev/tty
                    
                    set +e 
                    
                    # Truy xuất nhanh UUID trực tiếp từ Database
                    target_uuid=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE user_key LIKE '$target_del:%' AND node_type IN ('tuic', 'vless') LIMIT 1;" | cut -d':' -f2 | tr -d '\r')
                    
                    # Xử lý ngoại lệ nếu user chỉ tồn tại ở mỗi node Hysteria2 (không có cấu trúc UUID)
                    if [ -z "$target_uuid" ]; then target_uuid="NO_UUID_FOUND"; fi
                    
                    if [ -z "$port" ]; then
                        # Dọn dẹp an toàn trên file config.json
                        jq "(.inbounds[] | select(has(\"users\")).users) |= map(select((.name // \"\") != \"$target_del\" and (.uuid // \"\") != \"$target_uuid\"))" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                        
                        # Xóa toàn bộ dữ liệu của User này trong DB cực kỳ gọn gàng
                        sqlite3 $DB_FILE "DELETE FROM users WHERE user_key LIKE '$target_del:%';"
                        
                        systemctl restart sing-box
                        echo -e "${GREEN} Đã dọn sạch User [$target_del] khỏi TOÀN BỘ các Node!${NC}"
                        sleep 3
                    else
                        # Dọn dẹp trên file config.json theo Port chỉ định
                        jq "(.inbounds[] | select(.listen_port == $port and has(\"users\")).users) |= map(select((.name // \"\") != \"$target_del\" and (.uuid // \"\") != \"$target_uuid\"))" $CONFIG_FILE > tmp.json && [ -s tmp.json ] && mv tmp.json $CONFIG_FILE || rm -f tmp.json
                        
                        # Xóa trong DB theo Port
                        sqlite3 $DB_FILE "DELETE FROM users WHERE port=$port AND user_key LIKE '$target_del:%';"
                        
                        systemctl restart sing-box
                        echo -e "${GREEN} Đã xóa User [$target_del] khỏi cổng $port!${NC}"
                        sleep 3
                    fi
                    
                    set -e 
                fi
            fi
            ;;
        9) create_swap ;;
        10) issue_cloudflare_cert ;;
        11) 
            systemctl start sing-box
            echo -e "${GREEN} Đã BẬT dịch vụ Sing-box!${NC}"
            sleep 3 
            ;;
        12) 
            systemctl stop sing-box
            echo -e "${YELLOW} Đã DỪNG dịch vụ Sing-box!${NC}"
            sleep 3 
            ;;
        13) 
            systemctl restart sing-box
            echo -e "${GREEN} Đã KHỞI ĐỘNG LẠI dịch vụ Sing-box thành công!${NC}"
            sleep 3 
            ;;
        14) 
            uninstall_system 
            ;;
        15)
            update_script
            ;;
        16) toggle_user_status ;;
        17) config_webhook ;;
        0) exit 0 ;;
        *) ;;
    esac
    main_menu
}
if [ -f "$SCRIPT_PATH" ]; then main_menu; else check_and_update_system; fi
