// Local compatibility fixture derived from LumaCore's existing Xtream contract.
// Only fictional metadata and dummy credentials; not a provider certification.
const http = require('http');
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://localhost');
  res.setHeader('content-type', 'application/json');
  if (u.pathname !== '/player_api.php') { res.writeHead(501); return res.end(JSON.stringify({error:'Path not modeled'})); }
  if (u.searchParams.get('username') !== 'fixture' || u.searchParams.get('password') !== 'fixture') return res.end(JSON.stringify({user_info:{auth:0}}));
  const a = u.searchParams.get('action');
  const responses = {
    get_live_categories:[{category_id:'1',category_name:'World'}],
    get_vod_categories:[{category_id:'2',category_name:'Hollywood'}],
    get_series_categories:[{category_id:'3',category_name:'English Series'}],
    get_live_streams:[{stream_id:11,name:'World Journal',category_id:'1',stream_icon:''}],
    get_vod_streams:[{stream_id:22,name:'The Quiet Earth (2025)',category_id:'2',container_extension:'mp4',year:'2025'}],
    get_series:[{series_id:33,name:'Orbit',category_id:'3',plot:'A fictional series for compatibility checks.'}],
    get_vod_info:{info:{plot:'An original fixture description.',releasedate:'2025-03-01'},movie_data:{stream_id:22,container_extension:'mp4'}},
    get_series_info:{info:{plot:'An original series fixture.'},episodes:{'2':[{id:332,title:'Chapter Three',season:2,episode_num:1,container_extension:'mp4',info:{plot:'Across seasons.'}}],'1':[{id:331,title:'Chapter One',season:1,episode_num:1,container_extension:'mp4',info:{plot:'The beginning.'}}]}}
  };
  if (!a) return res.end(JSON.stringify({user_info:{auth:1,status:'Active'}}));
  if (!(a in responses)) { res.writeHead(501); return res.end(JSON.stringify({error:'Action not modeled'})); }
  res.end(JSON.stringify(responses[a]));
}).listen(process.env.PORT);
