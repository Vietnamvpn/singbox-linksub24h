#!/bin/bash

# Đường dẫn lưu trữ hệ thống
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
DB_FILE="$CONFIG_DIR/proxy_data.db"
SCRIPT_PATH="/usr/local/bin/box-tool"

# Hàm lấy IP thực của VPS
get_ip() {
    echo $(curl -s ifconfig.me)
}

# --- PHẦN 1: CÀI ĐẶT HỆ THỐNG ---
install_system() {
    clear
    echo "========================================="
    echo " BẮT ĐẦU CÀI ĐẶT SING-BOX & CÁC TIỆN ÍCH "
    echo "========================================="
    
    # Cập nhật và cài đặt các thư viện cần thiết
    apt update && apt install -y curl jq wget ufw openssl sqlite3
    
    # Tạo thư mục cấu hình
    mkdir -p $CONFIG_DIR
    
    # Tải Sing-box core bản mới nhất
    echo "--> Đang tải Sing-box core..."
    wget -O /usr/local/bin/sing-box https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64
    chmod +x /usr/local/bin/sing-box
    
    # Khởi tạo file cấu hình JSON trống chuẩn hóa
    cat << 'EOF' > $CONFIG_FILE
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF

    # Khởi tạo cơ sở dữ liệu SQLite
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, node_type TEXT, port INTEGER, user_key TEXT);"

    # Tự động tạo Chứng chỉ SSL tự ký
    echo "--> Đang khởi tạo chứng chỉ SSL tự ký (Thời hạn 10 năm)..."
    openssl req -x509 -nodes -newkey rsa:2048 -keyout $CONFIG_DIR/private.key -out $CONFIG_DIR/cert.pem -days 3650 -subj "/CN=bing.com" &>/dev/null

    # Tạo Systemd Service để Sing-box chạy ngầm
    cat << 'EOF' > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box &>/dev/null

    # Tự sao chép chính mã nguồn này vào hệ thống để làm menu gọi lệnh 'box-tool'
    cp "$0" $SCRIPT_PATH
    chmod +x $SCRIPT_PATH
    
    echo "--> Cài đặt lõi thành công!"
    echo "========================================="
    sleep 2
    
    # Chạy trình thuật sĩ tạo Node đầu tiên
    node_wizard
}

# --- PHẦN 2: TRÌNH THUẬT SĨ TẠO NODE (WIZARD) ---
node_wizard() {
    while true; do
        clear
        echo "========================================="
        echo "     TRÌNH KHỞI TẠO NODE PROXY MỚI       "
        echo "========================================="
        echo "1. Tạo Node Hysteria2"
        echo "2. Tạo Node TUIC v5"
        read -p "Chọn loại Node muốn tạo (1-2): " node_choice
        
        read -p "Nhập Cổng (Port) cho Node này: " port
        
        # Kiểm tra trùng cổng
        port_check=$(jq "[.inbounds[] | select(.listen_port == $port)] | length" $CONFIG_FILE)
        if [ "$port_check" -ne 0 ]; then
            echo "❌ Cổng $port đã được sử dụng bởi Node khác! Hãy chọn cổng khác."
            sleep 2
            continue
        fi

        ufw allow $port/udp &>/dev/null
        IP=$(get_ip)
        
        if [ "$node_choice" == "1" ]; then
            read -p "Nhập tên User đầu tiên cho Hy2: " hy_user
            read -p "Nhập mật khẩu Hy2: " hy_pass
            
            jq -i ".inbounds += [{\"type\": \"hysteria2\", \"tag\": \"hy2-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"name\": \"$hy_user\", \"password\": \"$hy_pass\"}], \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\"}}]" $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('hysteria2', $port, '$hy_user:$hy_pass');"
            
            echo -e "\n✅ ĐÃ MỞ NODE HY2 CỔNG $port!"
            echo "🔗 Link User [$hy_user]: hysteria2://$hy_pass@$IP:$port?insecure=1&sni=bing.com#Hy2-$hy_user-$port"
            
        elif [ "$node_choice" == "2" ]; then
            read -p "Nhập mật khẩu cho User đầu tiên của TUIC: " tuic_pass
            uuid=$(cat /proc/sys/kernel/random/uuid)
            
            jq -i ".inbounds += [{\"type\": \"tuic\", \"tag\": \"tuic-$port\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{\"uuid\": \"$uuid\", \"password\": \"$tuic_pass\"}], \"congestion_control\": \"bbr\", \"tls\": {\"enabled\": true, \"certificate_path\": \"$CONFIG_DIR/cert.pem\", \"key_path\": \"$CONFIG_DIR/private.key\", \"alpn\": [\"h3\"]}}]" $CONFIG_FILE
            sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('tuic', $port, '$uuid:$tuic_pass');"
            
            echo -e "\n✅ ĐÃ MỞ NODE TUIC V5 CỔNG $port!"
            echo "🔗 Link User [${uuid:0:8}]: tuic://$uuid:$tuic_pass@$IP:$port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=bing.com&allow_insecure=1#TUIC-${uuid:0:8}-$port"
        else
            echo "Lựa chọn không hợp lệ!"
            sleep 2
            continue
        fi
        
        echo "========================================="
        read -p "Bạn có muốn tiếp tục mở thêm Cổng/Node khác không? (y/n): " ext_choice
        if [[ "$ext_choice" != "y" && "$ext_choice" != "Y" ]]; then
            systemctl restart sing-box
            ufw reload &>/dev/null
            break
        fi
    done
}

# --- PHẦN 3: CÁC HÀM QUẢN LÝ USER RIÊNG BIỆT ---
add_user_to_node() {
    clear
    echo "========================================="
    echo "       THÊM USER VÀO NODE CÓ SẴN         "
    echo "========================================="
    read -p "Nhập số Cổng (Port) của Node muốn thêm User: " port
    
    exists=$(jq "[.inbounds[] | select(.listen_port == $port)] | length" $CONFIG_FILE)
    if [ "$exists" -eq 0 ]; then
        echo "❌ Không tìm thấy Node nào đang chạy trên cổng $port!"
        sleep 2
        return
    fi
    
    type=$(jq -r ".inbounds[] | select(.listen_port == $port) | .type" $CONFIG_FILE)
    
    if [ "$type" == "hysteria2" ]; then
        read -p "Nhập tên User mới: " uname
        read -p "Nhập mật khẩu mới: " upass
        jq -i "(.inbounds[] | select(.listen_port == $port).users) += [{\"name\": \"$uname\", \"password\": \"$upass\"}]" $CONFIG_FILE
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('hysteria2', $port, '$uname:$upass');"
        echo "✅ Thêm thành công User [$uname] vào cổng Hy2 [$port]!"
    elif [ "$type" == "tuic" ]; then
        read -p "Nhập mật khẩu cho User mới: " upass
        uuid=$(cat /proc/sys/kernel/random/uuid)
        jq -i "(.inbounds[] | select(.listen_port == $port).users) += [{\"uuid\": \"$uuid\", \"password\": \"$upass\"}]" $CONFIG_FILE
        sqlite3 $DB_FILE "INSERT INTO users (node_type, port, user_key) VALUES ('tuic', $port, '$uuid:$upass');"
        echo "✅ Thêm thành công User mới vào cổng TUIC [$port]!"
        echo "🔑 UUID cấp phát: $uuid"
    fi
    systemctl restart sing-box
    sleep 3
}

delete_user_from_node() {
    clear
    echo "========================================="
    echo "       XÓA USER KHỎI NODE CÓ SẴN         "
    echo "========================================="
    read -p "Nhập số Cổng (Port) của Node muốn cấu hình: " port
    
    exists=$(jq "[.inbounds[] | select(.listen_port == $port)] | length" $CONFIG_FILE)
    if [ "$exists" -eq 0 ]; then
        echo "❌ Không tìm thấy Node nào trên cổng $port!"
        sleep 2
        return
    fi
    
    type=$(jq -r ".inbounds[] | select(.listen_port == $port) | .type" $CONFIG_FILE)
    echo -e "\n--- Danh sách User hiện có trên cổng $port ---"
    
    if [ "$type" == "hysteria2" ]; then
        jq -r ".inbounds[] | select(.listen_port == $port).users[].name" $CONFIG_FILE
        echo "----------------------------------------"
        read -p "Nhập CHÍNH XÁC tên User muốn xóa: " uname
        jq -i "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.name != \"$uname\"))" $CONFIG_FILE
        sqlite3 $DB_FILE "DELETE FROM users WHERE port=$port AND user_key LIKE '$uname:%';"
        echo "✅ Đã xóa user [$uname] khỏi cổng $port!"
    elif [ "$type" == "tuic" ]; then
        jq -r ".inbounds[] | select(.listen_port == $port).users[] | \"UUID: \(.uuid) | Pass: \(.password)\"" $CONFIG_FILE
        echo "----------------------------------------"
        read -p "Nhập CHÍNH XÁC chuỗi UUID muốn xóa: " uuid
        jq -i "(.inbounds[] | select(.listen_port == $port).users) |= map(select(.uuid != \"$uuid\"))" $CONFIG_FILE
        sqlite3 $DB_FILE "DELETE FROM users WHERE port=$port AND user_key LIKE '$uuid:%';"
        echo "✅ Đã xóa user có UUID [$uuid] khỏi cổng $port!"
    fi
    systemctl restart sing-box
    sleep 2
}

# --- PHẦN 4: MENU QUẢN LÝ TỔNG HỢP ---
main_menu() {
    clear
    echo "========================================="
    echo "    MENU QUẢN LÝ SING-BOX PROXY TOOL     "
    echo "========================================="
    echo " 1. Xem danh sách & Link TẤT CẢ các User"
    echo " 2. Xem LOG kết nối trực tiếp (Live Logs)"
    echo "----------------------------------------"
    echo " 3. [NODE] Thêm Node mới (Mở thêm Cổng)"
    echo " 4. [NODE] Xóa một Node (Đóng hẳn Cổng)"
    echo "----------------------------------------"
    echo " 5. [USER] Thêm người dùng vào Node có sẵn"
    echo " 6. [USER] Xóa người dùng khỏi Node"
    echo "----------------------------------------"
    echo " 7. Khởi động lại (Restart) Sing-box"
    echo " 8. Dừng / Chạy (Stop / Start) Dịch vụ"
    echo " 9. Cập nhật Core Sing-box bản mới nhất"
    echo " 10. Gỡ bỏ sạch sẽ hoàn toàn khỏi VPS"
    echo " 0. Thoát menu"
    echo "========================================="
    read -p "Nhập lựa chọn của bạn: " m_choice
    
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
                
                echo -e "\n📍 KHU VỰC CỔNG: $port [ Giao thức: ${type^^} ]"
                echo "-------------------------------------------------------"
                
                for ((i=0; i<user_count; i++)); do
                    user_obj=$(echo "$inbound" | jq ".users[$i]")
                    if [ "$type" == "hysteria2" ]; then
                        name=$(echo "$user_obj" | jq -r '.name')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🚀 User [$name]: hysteria2://$pass@$IP:$port?insecure=1&sni=bing.com#Hy2-$name-$port"
                    elif [ "$type" == "tuic" ]; then
                        uuid=$(echo "$user_obj" | jq -r '.uuid')
                        pass=$(echo "$user_obj" | jq -r '.password')
                        echo "🛸 User [${uuid:0:8}]: tuic://$uuid:$pass@$IP:$port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=bing.com&allow_insecure=1#TUIC-${uuid:0:8}-$port"
                    fi
                done
            done
            echo -e "\n======================================================="
            read -p "Nhấn Enter để quay lại menu..." ;;
        2)
            clear
            echo "=========================================================="
            echo "            XEM LOG KẾT NỐI THEO THỜI GIAN THỰC          "
            echo "👉 Nhấn tổ hợp phím [ Ctrl + C ] để THOÁT ra Menu chính.  "
            echo "=========================================================="
            sleep 1
            journalctl -u sing-box --no-hostname -n 50 -f ;;
        3) node_wizard ;;
        4)
            clear
            echo "=== XÓA BỎ HOÀN TOÀN MỘT NODE ==="
            read -p "Nhập số Cổng (Port) của node muốn xóa: " del_port
            jq -i "del(.inbounds[] | select(.listen_port == $del_port))" $CONFIG_FILE
            ufw delete allow $del_port/udp &>/dev/null
            sqlite3 $DB_FILE "DELETE FROM users WHERE port=$del_port;"
            systemctl restart sing-box
            echo "--> Đã dọn sạch cổng $del_port!"
            sleep 2 ;;
        5) add_user_to_node ;;
        6) delete_user_from_node ;;
        7) systemctl restart sing-box && echo "Đã Khởi động lại!" && sleep 1 ;;
        8) 
            clear
            echo "1. Dừng chạy (Stop)"
            echo "2. Kích hoạt chạy (Start)"
            read -p "Lựa chọn: " s_choice
            if [ "$s_choice" == "1" ]; then systemctl stop sing-box; else systemctl start sing-box; fi
            echo "Thao tác thành công!" && sleep 1 ;;
        9) 
            echo "--> Đang tải bản Sing-box mới nhất..."
            wget -O /usr/local/bin/sing-box https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64
            chmod +x /usr/local/bin/sing-box
            systemctl restart sing-box
            echo "Cập nhật thành công!" && sleep 2 ;;
        10)
            read -p "Bạn có chắc chắn muốn xóa SẠCH mọi thứ khỏi VPS? (y/n): " un_confirm
            if [[ "$un_confirm" == "y" || "$un_confirm" == "Y" ]]; then
                systemctl stop sing-box
                systemctl disable sing-box &>/dev/null
                rm -rf /usr/local/bin/sing-box $CONFIG_DIR /etc/systemd/system/sing-box.service $SCRIPT_PATH
                systemctl daemon-reload
                echo "Đã gỡ bỏ sạch sẽ hoàn toàn hệ thống proxy!"
                exit 0
            fi ;;
        *) exit 0 ;;
    esac
    main_menu
}

# --- PHẦN 5: KHỞI CHẠY ĐIỀU HƯỚNG ---
if [ -f "$SCRIPT_PATH" ]; then
    main_menu
else
    clear
    echo "================================================="
    echo "  CHÀO MỪNG BẠN ĐẾN VỚI SCRIPT TỰ ĐỘNG SING-BOX  "
    echo "================================================="
    echo " 1. Đồng ý và cài đặt toàn bộ hệ thống Node"
    echo " 0. Hủy bỏ quá trình"
    echo "================================================="
    read -p "Lựa chọn của bạn (0-1): " init_choice
    
    if [ "$init_choice" == "1" ]; then
        install_system
    else
        echo "Đã hủy bỏ cài đặt!"
        exit 0
    fi
fi
