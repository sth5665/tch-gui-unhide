--pretranslated: do not change this file

-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local common = require("common_helper")
local content_helper = require("web.content_helper")
local message_helper = require("web.uimessage_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")
local splitter = require("split")
local string,ngx,os = string,ngx,os
local tonumber = tonumber
local concat,sort = table.concat,table.sort
local find,format,gmatch,match,lower = string.find,string.format,string.gmatch,string.match,string.lower
---@diagnostic disable-next-line: undefined-field
local untaint = string.untaint

local lp = require("web.lp")
lp.setpath("/www/snippets/")

local agentSTA = {}
local multiap = proxy.getPN("Device.Services.X_TELSTRA_MultiAP.Agent.",true)
if multiap then
  for _,agent in ipairs(multiap) do
    local agentname = format("%s",proxy.get(agent["path"].."Alias")[1].value)
    if agentname ~= "" then
      local BSSID2GHz = format("%s",proxy.get(agent["path"].."BSSID2GHZ")[1].value)
      local staPath = agent["path"].."STA."
      local staInfo = proxy.get(staPath)
      local staList = content_helper.convertResultToObject(staPath,staInfo)
      for _,sta_v in ipairs(staList) do
        local staMAC = string.lower(sta_v.MACAddress)
        local wifiBand = sta_v.BSSID == BSSID2GHz and " - 2.4GHz" or " - 5GHz"
        agentSTA[staMAC] = agentname..wifiBand
      end
    end
  end
end

local radios = {}
for _,v in ipairs(proxy.getPN("rpc.wireless.radio.", true)) do
  local radio = match(v.path, "rpc%.wireless%.radio%.@([^%.]+)%.")
  if radio then
    local band = proxy.get(v.path.."band")
    if band then
      radios[radio] = untaint(band[1].value)
    end
  end
end

local function getInterfaceType(data)
  if data["Radio"] and data["Radio"] ~= "" then
    local key = untaint(data["Radio"])
    local radio = radios[key]
    if radio then
      return "Wireless - "..radio
    else
      return "Wireless - "..key
    end
  elseif match(data["L2Interface"],"eth*") then
    local agentWiFiBand = agentSTA[data["MACAddress"]]
    if agentWiFiBand then
      return agentWiFiBand
    else
      return format("Ethernet - %s",data["Port"])
    end
  elseif match(data["L2Interface"],"moca*") then
    return "MoCA"
  else
    return data["L2Interface"]
  end
end

local devices_columns = {
  {--[1]
    header = T"Status",
    name = "state",
    param = "State",
    type = "light",
    readonly = true,
    attr = { input = { class="span1" } },
  },
  {--[2]
    header = T"Hostname",
    name = "FriendlyName",
    param = "FriendlyName",
    type = "text",
    attr = { input = { class="span3" } },
  },
  {--[3]
    header = T"IPv4",
    name = "ipv4",
    param = "IPv4",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
  },
  {--[4]
    header = T"IPv6",
    name = "ipv6",
    param = "IPv6",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
  },
  {--[5]
    header = T"MAC",
    name = "macaddress",
    param = "MACAddress",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
    additional_class = 'data-type="mac"',
  },
  {--[6]
    header = T"Interface",
    name = "interfacetype",
    param = "InterfaceType",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
  },
  {--[7]
    header = T"Connected",
    name = "ConnectionTime",
    param = "ConnectedTime",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
  },
  {--[8]
    header = T"Lease Time",
    name = "dhcpLeaseTime",
    param = "DhcpLeaseTime",
    type = "text",
    readonly = true,
    attr = { input = { class="span1" } },
  },
}

local getargs = ngx.req.get_uri_args()

local sortcol
if (getargs.sort) then
  sortcol = getargs.sort:untaint()
else
  sortcol = "FriendlyName"
end
local sortfunc
if sortcol == "FriendlyName" then
  sortfunc = function(a,b)
    return lower(a.FriendlyName or "") < lower(b.FriendlyName or "")
  end
elseif sortcol == "IPv4" then
  local ipv4ToNumber = function(a)
    local ipv4
    if (a.IPv4 == "") then
      ipv4 = a.DhcpLeaseIP
    else
      ipv4 = a.IPv4
    end
    local bits = {ipv4:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
    if #bits == 4 then
      return tonumber(format("%03d%03d%03d%03d",bits[1],bits[2],bits[3],bits[4]))
    else
      return 0
    end
  end
  sortfunc = function(a,b)
    return ipv4ToNumber(a) < ipv4ToNumber(b)
  end
elseif sortcol == "IPv6" then
  local ipv6ToString = function(addr)
    local a = splitter.first_and_rest(untaint(addr)," ")
    local emptyIdx = 0
    local bits = {}
    for bit in string.gmatch(a,"(%w*):*") do
      if bit == "" then
        emptyIdx = #bits+1
      end
      bits[#bits+1] = ('0'):rep(4-#bit)..bit
    end
    if emptyIdx > 0 then
      for _ = emptyIdx+1,8,1 do
        bits[emptyIdx] = bits[emptyIdx].."0000"
      end
    end
    local retval = ""
    for _,b in ipairs(bits) do
      if retval == "" then
        retval = b
      else
        retval = retval..b
      end
    end
    return retval
  end
  sortfunc = function(a,b)
    return ipv6ToString(a.IPv6) < ipv6ToString(b.IPv6)
  end
elseif sortcol == "InterfaceType" then
  sortfunc = function(a,b)
    local aIface = getInterfaceType(a)
    local bIface = getInterfaceType(b)
    if aIface == bIface then
      return lower(a.FriendlyName or "") < lower(b.FriendlyName or "")
    else
      return aIface < bIface
    end
  end
else
  sortfunc = sortcol
end

local connected
local connectedAction
if (getargs.connected) then
  connected = getargs.connected:untaint()
else
  connected = "Active"
end
if connected == "Active" then
  connectedAction = "All"
else
  connectedAction = "Active"
end

local mac_vendor = {}
if getargs.cache and getargs.cache == "clear" then
  proxy.set("rpc.gui.mac.clear_cache","1")
else
  local file = proxy.get("rpc.gui.mac.cached")
  if file then
    local pattern = "([%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]:[%x][%x]) (.*)"
    for line in gmatch(file[1].value,"([^\n]*)\n") do
      local mac,name = match(untaint(line),pattern)
      if mac and name and name ~= "" then
        mac_vendor[mac] = name
      end
    end
  end
end

local device_valid = {}
local devices_options = {
  canEdit = true,
  canAdd = false,
  canDelete = false,
  tableid = "devices",
  basepath = "rpc.hosts.host.",
  sorted = sortfunc,
}

local devices_filter = function(data)
  if data["L2Interface"] == "" or (connected == "Active" and data["State"] == "0") then
    return false
  end
  data["InterfaceType"] = getInterfaceType(data)
  if data["IPv4"] == "" or data["IPv6"] == "" then
    if data["DhcpLeaseIP"] ~= "" then
      local chunks = {data["DhcpLeaseIP"]:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
      if (#chunks == 4) then
        data["IPv4"] = data["DhcpLeaseIP"]
      else
        data["IPv6"] = data["DhcpLeaseIP"]
      end
    end
  end
  if data["IPv6"] and find(data["IPv6"]," ") then
    local addresses = splitter.split(untaint(data["IPv6"])," ")
    sort(addresses,function(a,b)
      return a < b
    end)
    data["IPv6"] = concat(addresses,"<br>")
  end
  local mac = untaint(data["MACAddress"])
  data["MACAddress"] = format("<span class='maccell' id='%s'><span class='macaddress'>%s</span><i class='macvendor'>%s</i><span>",mac:gsub(":",""),mac,mac_vendor[mac] or "")
  return true
end

local dumaOS = proxy.get("uci.dumaos.tr69.dumaos_enabled")
if dumaOS and dumaOS[1].value ~= "1" then
 devices_columns[#devices_columns+1] = { --[9]
    header = T"Priority<span class='icon-question-sign' title='Prioritize outgoing traffic'></span>",
    name = "priority",
    param = "Priority",
    type = "switch",
    readonly = false,
    attr = { input = { class="span3" } },
  }
end

local devices_data,devices_helpmsg = post_helper.handleTableQuery(devices_columns,devices_options,devices_filter,nil,device_valid)

for k,v in pairs (devices_data) do
  devices_data[k][1] = format("%s",v[1])
  devices_data[k][5] = format("%s",v[5])
  if v[8] ~= "" and v[7] ~= "" then
    v[8] = common.secondsToTime(tonumber(v[8])- (os.time()- tonumber(v[7]))%tonumber(v[8])) or T"Infinite"
  else
    v[8]="-"
  end
  if v[7] ~= "" then
    v[7] = common.secondsToTime(os.time()- tonumber(v[7]))
  else
    v[7] = "-"
  end
end

local interval = 10
if ngx.var.request_method == "POST" and ngx.var.content_type and match(ngx.var.content_type,"application/x%-www%-form%-urlencoded") then
  local action = ngx.req.get_post_args().action
  if action == "TABLE-EDIT" then
    ---@diagnostic disable-next-line: cast-local-type
    interval = nil
  end
end

ngx.print(ui_helper.createHeader(T"Devices",false,true,interval),'\
<style>.macvendor{display:block;font-size:8px;line-height:8px;}</style>\
<div class="modal-body update">\
'); lp.include("tabs-devices.lp") ngx.print('\
  <form class="form-horizontal" method="post" action="modals/device-modal.lp?sort=',sortcol,'&connected=',connected,'">',
    ui_helper.createMessages(message_helper.popMessages()),'\
    <fieldset>',
      ui_helper.createTable(devices_columns,devices_data,devices_options,nil,devices_helpmsg),'\
    </fieldset>\
  </form>\
</div>',
ui_helper.createFooter(),'\
<script>\
$("#devices .maccell").each(function(index,cell){\
  var vendor=$("#"+cell.id+" .macvendor");\
  if (vendor.text() === ""){\
    var mac=$("#"+cell.id+" .macaddress").text();\
    $.post("/ajax/vendor.lua?mac="+mac,[tch.elementCSRFtoken()],function(data){\
      vendor.text(data["name"]);\
    },"json")\
    .fail(function(response){\
      vendor.text("Vendor lookup failed :-(");\
    });\
  };\
});\
var hdrs = document.getElementsByTagName("th");\
for(var i=0;i<hdrs.length;i++){\
  var text=hdrs[i].innerText;\
  var sort="";\
  var title="";\
  var connected="',connected,'";\
  switch(text){\
    case "Status":sort="',sortcol,'";connected="',connectedAction,'";title="Show ',connectedAction,'";break;\
    case "Hostname":sort="FriendlyName";break;\
    case "IPv4":sort="IPv4";break;\
    case "IPv6":sort="IPv6";break;\
    case "MAC":sort="MACAddress";break;\
    case "Interface":sort="InterfaceType";break;\
    case "Connected":sort="ConnectedTime";break;\
    default:sort="";break;\
  }\
  if (sort!="") {\
    if (title=="") {\
      title="Sort by "+text;\
    }\
    hdrs[i].innerHTML=\'<a href="#" title="\'+title+\'" data-remote="modals/device-modal.lp?sort=\'+sort+\'&connected=\'+connected+\'">\'+text+\'</a>\';\
    hdrs[i].setAttribute("class","nav");\
  }\
}\
$("#Refresh_id").html("<i class=\'icon-trash\'></i> Clear MAC cache").removeClass("modal-action-refresh").click(function(){\
  tch.loadModal($(".modal form").attr("action")+"&cache=clear");\
});\
</script>\
');
