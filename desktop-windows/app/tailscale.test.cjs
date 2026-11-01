const test=require('node:test'),assert=require('node:assert/strict');const {available}=require('./tailscale.cjs');
const host='desktop.example.ts.net',proxy='http://127.0.0.1:48291';
const config=handlers=>({TCP:{'8443':{HTTPS:true}},Web:{[host+':8443']:{Handlers:handlers}}});
test('Tailscale setup and cleanup reserve only an unused port or the exclusive app route',()=>{
 assert.equal(available({},host,48291),true);
 assert.equal(available(config({'/':{Proxy:proxy}}),host,48291),true);
 assert.equal(available(config({'/':{Proxy:proxy+'/'}}),host,48291),true);
 assert.equal(available(config({'/':{Proxy:'http://127.0.0.1:3000'}}),host,48291),false);
 assert.equal(available(config({'/':{Proxy:proxy},'/other':{Proxy:'http://127.0.0.1:3000'}}),host,48291),false);
 assert.equal(available({Web:{[host+':8443']:{Handlers:{'/':{Proxy:'http://127.0.0.1:3000'}}}}},host,48291),false);
});
