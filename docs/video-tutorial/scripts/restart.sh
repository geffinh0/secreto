for pid in $(ps -eo pid,args | awk '$2=="python3" && ($3=="mock_runner.py" || $3=="main.py") {print $1}'); do kill $pid; done; sleep 1
cd /tmp/claude-0/demo && rm -f demo.db && (setsid nohup python3 mock_runner.py > mock.log 2>&1 &) ; sleep 2
cd /home/user/secreto/backend && (env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy SM_DB_PATH=/tmp/claude-0/demo/demo.db SUPERLIVE_BASE_URL=http://127.0.0.1:9100/api/v1/ setsid nohup python3 main.py > /tmp/claude-0/demo/backend.log 2>&1 &) ; sleep 3
curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/docs; curl -s -o /dev/null -w "%{http_code}\n" localhost:3000/
curl -s -o /dev/null localhost:3000/ || (cd /home/user/secreto/build/web && setsid nohup python3 -m http.server 3000 --bind 127.0.0.1 > /tmp/claude-0/demo/web.log 2>&1 &); sleep 1
