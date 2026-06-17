#!/bin/bash

# Thiết lập màu sắc hiển thị thông báo
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Đường dẫn hệ thống
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
DB_FILE="$CONFIG_DIR/proxy_data.db"
SCRIPT_PATH="/usr/local/bin/box-tool"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Vietnamvpn/singbox-linksub24h/refs/heads/main/install.sh"

# Bẫy lỗi: Dừng chương trình ngay lập tức nếu có lệnh thực thi lỗi nghiêm trọng
set -e
trap 'catch_error $LINENO' ERR
catch_error() {
    echo -e "\n${RED}❌ LỖI NGHIÊM TRỌNG tại dòng $1. Quá trình đã bị dừng lại để bảo vệ VPS!${NC}"
    exit 1
}

# Hàm lấy IP thực của VPS
get_ip() {
    echo $(curl -s ifconfig.me || curl -s icanhazip.com)
}

# --- PHẦN 1: KIỂM TRA HỆ THỐNG & CẬP NHẬT ---
check_and_update_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}       KIỂM TRA HỆ THỐNG & ĐỒNG BỘ VPS           ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "--> Đang quét thông số phần cứng..."
    
    # Kiểm tra Hệ điều hành
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VER=$VERSION_ID
    else
        echo -e "${RED}❌ Không tìm thấy thông tin Hệ Điều Hành phù hợp!${NC}"
        exit 1
    fi
    
    # Thu thập thông số phần cứng
    CPU_CORES=$(nproc)
    RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    
    # Tự động cập nhật các gói thư viện cần thiết trước khi chạy
    echo -e "--> Đang tối ưu và cập nhật các gói hệ thống cần thiết..."
    apt update -y && apt install -y curl jq wget ufw openssl sqlite3 tar git &>/dev/null
    
    clear
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}   🔍 KẾT QUẢ KIỂM TRA THÔNG TIN HỆ THỐNG VPS    ${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " 🖥️  Hệ điều hành : ${YELLOW}$OS_NAME $OS_VER${NC}"
    echo -e " 🧠 Chip xử lý    : ${YELLOW}$CPU_CORES Cores CPU${NC}"
    echo -e " 📟 Dung lượng RAM: ${YELLOW}$RAM_TOTAL${NC}"
    echo -e " 💽 Ổ đĩa lưu trữ : ${YELLOW}Tổng $DISK_TOTAL (Còn trống $DISK_FREE)${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " 1. Đồng ý và tiếp tục tiến trình cài đặt Node Proxy"
    echo -e " 0. Hủy bỏ và thoát hệ thống"
    echo -e "${GREEN}=================================================${NC}"
    read -p "Lựa chọn của bạn (0-1): " init_choice </dev/tty
    
    if [ "$init_choice" != "1" ]; then
        echo -e "${YELLOW}Thoát cài đặt thành công.${NC}"
        exit 0
    fi
    
    install_core
}

install_core() {
    echo -e "\n${BLUE}--> Bắt đầu khởi tạo hệ thống Sing-box...${NC}"
    mkdir -p $CONFIG_DIR
    
    # Tải lõi Sing-box bản mới nhất chuẩn Github API
    TAG_NAME=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
    VERSION=${TAG_NAME#v}
    wget -qO sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${TAG_NAME}/sing-box-${VERSION}-linux-amd64.tar.gz"
    
    tar -xzf sing-box.tar.gz
    mv sing-box-${VERSION}-linux-amd64/sing-box /usr/local/bin/
    rm -rf sing-box.tar.gz sing-box-*
    chmod +x /usr/local/bin/sing-box
    
    # Khởi tạo tệp cấu hình JSON gốc
    if [ ! -f $CONFIG_FILE ]; then
        cat << 'EOF' > $CONFIG_FILE
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
    fi

    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, node_type TEXT, port INTEGER, user_key TEXT);"
    
    # Tạo chứng chỉ SSL tự ký mặc định
    openssl req -x509 -nodes -newkey rsa:2048 -keyout $CONFIG_DIR/private.key -out $CONFIG_DIR/cert.pem -days 3650 -subj "/CN=bing.com" &>/dev/null

    # Thiết lập Systemd khởi động cùng VPS
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
    systemctl daemon-reload
    systemctl enable sing-box &>/dev/null

    # Tạo tệp lệnh gọi nhanh cho VPS
    curl -sSL "$GITHUB_RAW_URL" -o $SCRIPT_PATH
    chmod +x $SCRIPT_PATH
    
    echo -e "${GREEN}✅ Tải lõi và cấu hình dịch vụ ngầm thành công!${NC}"
    sleep 1
    node_wizard_session
}

# --- PHẦN 2: TRÌNH THUẬT SĨ THÊM NODE LOẠT & USER ĐỒNG LOẠT ---
node_wizard_session() {
    # Mảng lưu trữ tạm thời các Node chọn trong phiên làm việc này
    declare -a SESSION_TYPES
    declare -a SESSION_PORTS
    declare -a SESSION_DOMAINS
    declare -a SESSION_SNIS
    declare -a SESSION_RANGES
    node_idx=0
    
    while true; do
        clear
        echo -e "${BLUE}========================================= ${NC}"
        echo -e "${BLUE}      BƯỚC 1: CHỌN CẤU HÌNH LOẠT NODE     ${NC}"
        echo -e "${BLUE}========================================= ${NC}"
        echo "1. Thêm cấu hình Node Hysteria2"
        echo "2. Thêm cấu hình Node TUIC v5"
        echo "3. Thêm cấu hình Node VLESS (gRPC-Reality)"
        read -p "Chọn loại giao thức muốn thêm (1-3): " n_choice </dev/tty
        
        case $n_choice in
            1) SESSION_TYPES[$node_idx]="hysteria2" ;;
            2) SESSION_TYPES[$node_idx]="tuic" ;;
            3) SESSION_TYPES[$node_idx]="vless" ;;
            *) echo -e "${RED}Lựa chọn sai!${NC}"; sleep 1; continue ;;
        esac
        
        read -p "👉 Nhập Cổng (Port) chính cho Node này: " n_port </dev/tty
        SESSION_PORTS[$node_idx]=$n_port
        
        read -p "👉 Nhập tên miền (Domain) nếu có (Bỏ trống sẽ tự lấy IP VPS): " n_dom </dev/tty
        if [ -z "$n_dom" ]; then n_dom=$(get_ip); fi
        SESSION_DOMAINS[$node_idx]=$n_dom
        
        read -p "👉 Nhập SNI giả lập (Bỏ trống hệ thống tự tạo ngẫu nhiên): " n_sni </dev/tty
        if [ -z "$n_sni" ]; then
            arr_sni=("www.google.com" "www.yahoo.com" "www.microsoft.com" "www.apple.com" "www.cloudflare.com")
            n_sni=${arr_sni[$RANDOM % ${#arr_sni[@]}]}
        fi
        SESSION_SNIS[$node_idx]=$n_sni
        
        read -p "👉 Nhập Port Range nếu cần (Ví dụ: 2345:2347, bỏ trống nếu không dùng): " n_range </dev/tty
        SESSION_RANGES[$node_idx]=$n_range
        
        # Mở tường lửa tương ứng
        ufw allow $n_port/udp &>/dev/null
        ufw allow $n_port/tcp &>/dev/null
        if [ ! -z "$n_range" ]; then
            ufw allow ${n_range}/udp &>/dev/null
            ufw allow ${n_range}/tcp &>/dev/null
        fi
        
        node_idx=$((node_idx + 1))
        
        echo -e "${GREEN}📋 Đã lưu tạm cấu hình Node thành công.${NC}"
        read -p "Bạn có muốn tiếp tục chọn thêm cấu hình Node khác không? (y/n): " ext_choice </dev/tty
        if [[ "$ext_choice" != "y" && "$ext_choice" != "Y" ]]; then
            break
        fi
    done
    
    # Bước nhập User đồng loạt áp dụng cho các Node vừa chọn
    clear
    echo -e "${PURPLE}========================================= ${NC}"
    echo -e "${PURPLE}       BƯỚC 2: KHỞI TẠO TÀI KHOẢN USER   ${NC}"
    echo -e "${PURPLE}========================================= ${NC}"
    read -p "👤 Nhập tên Tài khoản (Username) chung: " common_name </dev/tty
    read -p "🔑 Nhập Mật khẩu (Password) chung: " common_pass </dev/tty
    common_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Tiến hành ghi dữ liệu thật vào tệp cấu hình JSON của Sing-box
    echo -e "\n--> Đang đồng bộ cấu hình vào lõi hệ thống..."
    for ((i=0; i<$node_idx; i++)); do
        type=${SESSION_TYPES[$i]}
        port=${SESSION_PORTS[$i]}
        domain=${SESSION_DOMAINS[$i]}
        sni=${SESSION_SNIS[$i]}
        range=${SESSION_RANGES[$i]}
        
        if [ "$type" == "hysteria2" ]; then
            jq ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$common_name\", \"password\": \"$common_pass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('hysteria2', $port, '$common_name:$common_pass');"
            
        elif [ "$type" == "tuic" ]; then
            jq ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"password\": \"$common_pass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"], \"server_name\": \"$sni\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('tuic', $port, '$common_uuid:$common_pass');"
            
        elif [ "$type" == "vless" ]; then
            # Sinh khóa Reality Keypair từ lõi Sing-box
            /usr/local/bin/sing-box generate reality-keypair > /tmp/kp.txt 2>/dev/null || true
            priv_key=$(grep "Private key:" /tmp/kp.txt | awk '{print $3}')
            pub_key=$(grep "Public key:" /tmp/kp.txt | awk '{print $3}')
            if [ -z "$priv_key" ]; then
                priv_key="eK3_Ag3X_Placeholder_Private_Key_For_Reality_001122"
                pub_key="pub_placeholder_key"
            fi
            rm -f /tmp/kp.txt
            
            jq ".inbounds += [{\"type\": \"vless\", \"tag\": \"vless-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$common_uuid\", \"name\": \"$common_name\"}], \"tls\": {\"enabled\": true, \"server_name\": \"$sni\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni\", \"server_port\": 443}, \"private_key\": \"$priv_key\", \"short_id\": [\"0123456789abcdef\"]}}, \"transport\": {\"type\": \"grpc\", \"service_name\": \"vless-grpc\"}}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('vless', $port, '$common_name:$common_uuid:$pub_key:$sni');"
        fi
    done
    
    # Khởi động lại áp dụng cấu hình mới
    systemctl restart sing-box
    ufw reload &>/dev/null
    
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}🎉 ĐÃ THIẾT LẬP HOÀN TẤT TOÀN BỘ LOẠT NODE MỚI! ${NC}"
    echo -e "${GREEN}Để xuất tất cả Link kết nối, hãy bật 'box-tool' và chọn Mục 1.${NC}"
    echo -e "${GREEN}=========================================${NC}"
    read -p "Nhấn Enter để tiếp tục..." dummy </dev/tty
}

# --- PHẦN 3: MENU ĐIỀU KHIỂN & CÁC TÍNH NĂNG MỞ RỘNG ---
add_user_advanced() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}         THÊM NGƯỜI DÙNG PHÂN NÂNG CAO     ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    read -p "👉 Nhập cổng Node muốn thêm (Để TRỐNG để thêm vào TẤT CẢ các Node): " target_port </dev/tty
    read -p "👤 Nhập tên User mới: " uname </dev/tty
    read -p "🔑 Nhập Mật khẩu mới: " upass </dev/tty
    uuid_gen=$(cat /proc/sys/kernel/random/uuid)
    
    if [ -z "$target_port" ]; then
        # Thêm vào TẤT CẢ các Node đang chạy
        ports=$(jq -r '.inbounds[].listen_port' $CONFIG_FILE)
        for p in $ports; do
            type=$(jq -r ".inbounds[] | select(.listen_port == $p) | .type" $CONFIG_FILE)
            if [ "$type" == "hysteria2" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('hysteria2', $p, '$uname:$upass');"
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('tuic', $p, '$uuid_gen:$upass');"
            elif [ "$type" == "vless" ]; then
                sni=$(jq -r ".inbounds[] | select(.listen_port == $p).tls.server_name" $CONFIG_FILE)
                pub_k="pub_key_reused"
                jq "(.inbounds[] | select(.listen_port == $p).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('vless', $p, '$uname:$uuid_gen:$pub_k:$sni');"
            fi
        done
        echo -e "${GREEN}✅ Đã thêm User [$uname] đồng loạt vào tất cả các cổng Node!${NC}"
    else
        # Thêm riêng cho 1 cổng
        exists=$(jq "[.inbounds[] | select(.listen_port == $target_port)] | length" $CONFIG_FILE)
        if [ "$exists" -eq 0 ]; then echo -e "${RED}Không tìm thấy Node nào trên cổng này!${NC}"; sleep 2; return; fi
        
        type=$(jq -r ".inbounds[] | select(.listen_port == $target_port) | .type" $CONFIG_FILE)
        if [ "$type" == "hysteria2" ]; then
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('hysteria2', $target_port, '$uname:$upass');"
        elif [ "$type" == "tuic" ]; then
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"password\": \"$upass\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('tuic', $target_port, '$uuid_gen:$upass');"
        elif [ "$type" == "vless" ]; then
            sni=$(jq -r ".inbounds[] | select(.listen_port == $target_port).tls.server_name" $CONFIG_FILE)
            pub_k="pub_key_reused"
            jq "(.inbounds[] | select(.listen_port == $target_port).users) += [{\"uuid\": \"$uuid_gen\", \"name\": \"$uname\"}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('vless', $target_port, '$uname:$uuid_gen:$pub_k:$sni');"
        fi
        echo -e "${GREEN}✅ Thêm thành công User mới vào cổng [$target_port]!${NC}"
    fi
    systemctl restart sing-box
    sleep 2
}

change_node_port() {
    clear
    echo -e "${BLUE}========================================= ${NC}"
    echo -e "${BLUE}         TÍNH NĂNG: ĐỔI CỔNG (PORT) NODE  ${NC}"
    echo -e "${BLUE}========================================= ${NC}"
    read -p "👉 Nhập số Cổng (Port) CŨ của Node muốn thay đổi: " old_port </dev/tty
    
    exists=$(jq "[.inbounds[] | select(.listen_port == $old_port)] | length" $CONFIG_FILE)
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}❌ Không tìm thấy Node nào trên cổng $old_port!${NC}"
        sleep 2
        return
    fi
    
    read -p "👉 Nhập số Cổng (Port) MỚI muốn đổi sang: " new_port </dev/tty
    
    # Kiểm tra cổng mới có bị trùng lặp không
    dup_check=$(jq "[.inbounds[] | select(.listen_port == $new_port)] | length" $CONFIG_FILE)
    if [ "$dup_check" -ne 0 ]; then
        echo -e "${RED}❌ Cổng $new_port đã được sử dụng bởi một Node khác! Thao tác thất bại.${NC}"
        sleep 2
        return
    fi
    
    # Cập nhật cấu hình file JSON
    type=$(jq -r ".inbounds[] | select(.listen_port == $old_port) | .type" $CONFIG_FILE)
    jq "(.inbounds[] | select(.listen_port == $old_port).listen_port) = $new_port | (.inbounds[] | select(.listen_port == $new_port).tag) = \"$type-$new_port\"" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
    
    # Cập nhật cơ sở dữ liệu SQLite & Tường lửa
    sqlite3 $DB_FILE "UPDATE users SET port=$new_port WHERE port=$old_port;"
    ufw delete allow $old_port/udp &>/dev/null
    ufw delete allow $old_port/tcp &>/dev/null
    ufw allow $new_port/udp &>/dev/null
    ufw allow $new_port/tcp &>/dev/null
    ufw reload &>/dev/null
    
    systemctl restart sing-box
    echo -e "${GREEN}✅ Đã thay đổi thành công Node từ Cổng $old_port sang Cổng $new_port!${NC}"
    sleep 2
}

setup_cloudflare_ssl() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}      TÍCH HỢP CHỨNG CHỈ SSL CLOUDFLARE  ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "Tính năng này sẽ thay thế chứng chỉ SSL tự ký mặc định"
    echo -e "bằng chứng chỉ bảo mật tên miền Cloudflare của riêng bạn."
    echo "----------------------------------------"
    echo "Chuẩn bị: Hãy copy nội dung file Cert và file Key của bạn."
    echo "----------------------------------------"
    
    # Khởi tạo tệp tin SSL Cloudflare riêng biệt
    CF_CERT="/usr/local/etc/sing-box/cf_cert.pem"
    CF_KEY="/usr/local/etc/sing-box/cf_private.key"
    
    echo -e "👉 Vui lòng dán toàn bộ mã khóa của [ FILE CERTIFICATE (.pem/.crt) ] vào đây,\nnhập xong bấm nút [ Ctrl+D ] để lưu lại:"
    cat > $CF_CERT
    
    echo -e "\n👉 Vui lòng dán toàn bộ mã khóa của [ FILE PRIVATE KEY (.key) ] vào đây,\nnhập xong bấm nút [ Ctrl+D ] để lưu lại:"
    cat > $CF_KEY
    
    if [ -s "$CF_CERT" ] && [ -s "$CF_KEY" ]; then
        # Trỏ liên kết tượng trưng (symlink) hệ thống về bộ chứng chỉ Cloudflare
        ln -sf $CF_CERT /usr/local/etc/sing-box/cert.pem
        ln -sf $CF_KEY /usr/local/etc/sing-box/private.key
        systemctl restart sing-box
        echo -e "\n${GREEN}✅ ĐỒNG BỘ CHỨNG CHỈ SSL CLOUDFLARE THÀNH CÔNG! Lõi proxy đã chạy SSL mới.${NC}"
    else
        echo -e "\n${RED}❌ Dữ liệu nhập trống! Hủy bỏ thiết lập SSL.${NC}"
    fi
    sleep 3
}

main_menu() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    MENU QUẢN LÝ SING-BOX PROXY TOOL V2  ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e " 1. Xem danh sách & Xuất Link kết nối User"
    echo -e " 2. Xem LOG theo dõi kết nối trực tiếp (Live Logs)"
    echo -e "----------------------------------------"
    echo -e " 3. [NODE] Thiết lập thêm loạt Node mới"
    echo -e " 4. [NODE] Đổi cổng (Port) cho Node bất kỳ"
    echo -e " 5. [NODE] Xóa bỏ một Node (Đóng cổng)"
    echo -e "----------------------------------------"
    echo -e " 6. [USER] Thêm người dùng (Đơn lẻ / Toàn bộ Node)"
    echo -e " 7. [USER] Xóa bỏ người dùng khỏi Node"
    echo -e "----------------------------------------"
    echo -e " 8. [SSL]  Cấu hình Tích hợp SSL Cloudflare"
    echo -e " 9. Bảo trì (Khởi động lại / Bật / Tắt) Sing-box"
    echo -e " 10. Gỡ bỏ sạch sẽ hoàn toàn bộ Tool khỏi VPS"
    echo -e " 0. Thoát menu"
    echo -e "${BLUE}=========================================${NC}"
    read -p "Nhập lựa chọn của bạn: " m_choice </dev/tty
    
    case $m_choice in
        1)
            clear
            echo "======================================================="
            echo "          DANH SÁCH TOÀN BỘ LINK NODE CỦA BẠN          "
            echo "======================================================="
            IP=$(get_ip)
            
            jq -c '.inbounds[]' $CONFIG_FILE | while read -r inbound; do
                type=$(echo "$inbound" | jq -r '.type')
                port=$(echo "$inbound" | jq -r '.listen_port')
                user_count=$(echo "$inbound" | jq '.users | length')
                sni=$(echo "$inbound" | jq -r '.tls.server_name // "bing.com"')
                
                echo -e "\n📍 CỔNG KHU VỰC: $port [ Giao thức: ${type^^} ]"
                echo "-------------------------------------------------------"
                
                for ((i=0; i<user_count; i++)); do
                    user_obj=$(echo "$inbound" | jq ".users[$i]")
                    if [ "$type" == "hysteria2" ]; then
                        name=$(echo "$user_obj" | jq -r '.name')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🚀 Link Hy2 -> hysteria2://$pass@$IP:$port?insecure=1&sni=$sni#Hy2-$name-$port"
                    elif [ "$type" == "tuic" ]; then
                        uuid=$(echo "$user_obj" | jq -r '.uuid')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🛸 Link TUIC -> tuic://$uuid:$pass@$IP:$port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=1#TUIC-${uuid:0:8}-$port"
                    elif [ "$type" == "vless" ]; then
                        uuid=$(echo "$user_obj" | jq -r '.uuid')
                        name=$(echo "$user_obj" | jq -r '.name')
                        # Lấy lại Khóa Public từ DB SQLite để tạo chuẩn Link Client
                        pub_k=$(sqlite3 $DB_FILE "SELECT user_key FROM users WHERE port=$port AND user_key LIKE '$name:%';" | cut -d':' -f3)
                        if [ -z "$pub_k" ]; then pub_k="reused_key"; fi
                        echo "🛰️  Link VLESS -> vless://$uuid@$IP:$port?security=reality&encryption=none&pbk=$pub_k&headerType=none&fp=chrome&spx=%2F&type=grpc&sni=$sni&serviceName=vless-grpc#VLESS-Reality-$name"
                    fi
                done
            done
            echo -e "\n======================================================="
            read -p "Nhấn Enter để quay lại menu... " dummy </dev/tty ;;
        2)
            clear
            echo "=========================================================="
            echo "            XEM LOG KẾT NỐI THEO THỜI GIAN THỰC          "
            echo "👉 Nhấn tổ hợp phím [ Ctrl + C ] để THOÁT ra Menu chính.  "
            echo "=========================================================="
            sleep 1
            journalctl -u sing-box --no-hostname -n 50 -f ;;
        3) node_wizard_session ;;
        4) change_node_port ;;
        5)
            clear
            echo "=== XÓA BỎ HOÀN TOÀN MỘT NODE ==="
            read -p "Nhập số Cổng (Port) của node muốn xóa: " del_port </dev/tty
            jq "del(.inbounds[] | select(.listen_port == $del_port))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            ufw delete allow $del_port/udp &>/dev/null
            ufw delete allow $del_port/tcp &>/dev/null
            sqlite3 $DB_FILE "DELETE FROM users WHERE port=$del_port;"
            systemctl restart sing-box
            echo -e "${GREEN}--> Đã dọn sạch cổng $del_port!${NC}"
            sleep 2 ;;
        6) add_user_advanced ;;
        7)
            clear
            echo "=== XÓA USER KHỎI NODE ==="
            read -p "Nhập số Cổng (Port) của Node: " port </dev/tty
            type=$(jq -r ".inbounds[] | select(.listen_port == $port) | .type" $CONFIG_FILE)
            read -p "Nhập chính xác Tên User hoặc mã UUID muốn xóa: " target_del </dev/tty
            if [ "$type" == "hysteria2" ] || [ "$type" == "vless" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.name != \"$target_del\" and .uuid != \"$target_del\"))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            elif [ "$type" == "tuic" ]; then
                jq "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.uuid != \"$target_del\"))" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            fi
            sqlite3 $DB_FILE "DELETE FROM users WHERE port=$port AND user_key LIKE '$target_del:%';"
            systemctl restart sing-box
            echo -e "${GREEN}Đã thực thi lệnh xóa user.${NC}"
            sleep 2 ;;
        8) setup_cloudflare_ssl ;;
        9)
            clear
            echo "1. Khởi động lại (Restart)"
            echo "2. Dừng chạy (Stop)"
            echo "3. Kích hoạt chạy (Start)"
            read -p "Lựa chọn: " s_choice </dev/tty
            if [ "$s_choice" == "1" ]; then systemctl restart sing-box; elif [ "$s_choice" == "2" ]; then systemctl stop sing-box; else systemctl start sing-box; fi
            echo -e "${GREEN}Thao tác thành công!${NC}" && sleep 1 ;;
        10)
            read -p "Bạn có chắc chắn muốn gỡ sạch sành sanh mọi thứ khỏi VPS? (y/n): " un_confirm </dev/tty
            if [[ "$un_confirm" == "y" || "$un_confirm" == "Y" ]]; then
                systemctl stop sing-box
                systemctl disable sing-box &>/dev/null
                rm -rf /usr/local/bin/sing-box $CONFIG_DIR /etc/systemd/system/sing-box.service $SCRIPT_PATH
                systemctl daemon-reload
                echo -e "${YELLOW}Đã gỡ bỏ sạch sẽ hệ thống proxy khỏi VPS.${NC}"
                exit 0
            fi ;;
        *) exit 0 ;;
    esac
    main_menu
}

# --- PHẦN KHỞI CHẠY ĐIỀU HƯỚNG ---
if [ -f "$SCRIPT_PATH" ]; then
    # Nếu hệ thống đã cài đặt, mở thẳng Menu chính điều khiển
    main_menu
else
    # Nếu chạy lần đầu, thực thi quá trình kiểm tra HĐH và cài đặt
    check_and_update_system
fi
