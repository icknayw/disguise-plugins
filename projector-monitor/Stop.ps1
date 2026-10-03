foreach($port in @(18745,18746)){try{Invoke-RestMethod "http://localhost:$port/api/stop" -Method Post -Headers @{'X-Projector-Monitor'='1'} -TimeoutSec 3|Out-Null}catch{}}
