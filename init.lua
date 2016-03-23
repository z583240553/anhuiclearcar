local _M = {}
local bit = require "bit"
local cjson = require "cjson.safe"
local Json = cjson.encode

local strload

--Json的Key，用于协议帧头的几个数据
local cmds = {
  [0] = "length",
  [1] = "DTU_time",
  [2] = "DTU_status",
  [3] = "DTU_function",
  [4] = "device_address"
}

--Json的Key，用于清洁车云端显示状态
local status_cmds = {
  [1] = "MotorCurrent",
  [2] = "MotorControllerTemp",
  [3] = "CPUTemp",
  [4] = "SpeedSensorVol",
  [5] = "WorkVol",
  [6] = "SpeedGrade",
  [7] = "AcceleratorModel",
  [8] = "DriveStatus"
}

--FCS校验
function utilCalcFCS( pBuf , len )
  local rtrn = 0
  local l = len

  while (len ~= 0)
    do
    len = len - 1
    rtrn = bit.bxor( rtrn , pBuf[l-len] )
  end

  return rtrn
end

--将字符转换为数字
function getnumber( index )
   return string.byte(strload,index)
end

--编码 /in 频道的数据包
function _M.encode(payload)
  return payload
end

--解码 /out 频道的数据包
function _M.decode(payload)
	local packet = {['status']='not'}

	--FCS校验的数组(table)，用于逐个存储每个Byte的数值
	local FCS_Array = {}

	--用来直接读取发来的数值，并进行校验
	local FCS_Value = 0

	--strload是全局变量，唯一的作用是在getnumber函数中使用
	strload = payload

	--前2个Byte是帧头，正常情况应该为';'和'1'
	local head1 = getnumber(1)
	local head2 = getnumber(2)

	--当帧头符合，才进行其他位的解码工作
	if ( (head1 == 0x3B) and (head2 == 0x31) ) then

		--数据长度
		local templen = bit.lshift( getnumber(3) , 8 ) + getnumber(4)

		FCS_Value = bit.lshift( getnumber(templen+5) , 8 ) + getnumber(templen+6)

		--将全部需要进行FCS校验的Byte写入FCS_Array这个table中
		for i=1,templen+4,1 do
			table.insert(FCS_Array,getnumber(i))
		end

		--进行FCS校验，如果计算值与读取指相等，则此包数据有效；否则弃之
		if(utilCalcFCS(FCS_Array,#FCS_Array) == FCS_Value) then
			packet['status'] = 'SUCCESS'
		else
			packet = {}
			packet['status'] = 'FCS-ERROR'
			return Json(packet)
		end

		--数据长度
		--packet[ cmds[0] ] = templen
		--运行时长
		packet[ cmds[1] ] = bit.lshift( getnumber(5) , 24 ) + bit.lshift( getnumber(6) , 16 ) + bit.lshift( getnumber(7) , 8 ) + getnumber(8)
		--采集模式
		--[[local mode = getnumber(9)
		if mode == 1 then
			packet[ cmds[2] ] = 'Mode-485'
			else
			packet[ cmds[2] ] = 'Mode-232'
		end--]]
		--func为判断是 实时数据/参数/故障 的参数
		local func = getnumber(10)
		if func == 1 then  --解析状态数据
			--packet[ cmds[3] ] = 'func-status'
			--设备modbus地址
			--packet[ cmds[4] ] = getnumber(11)

			--local databuff_table={} --用来暂存上传的实际状态数据
			--local bitbuff_table={}  --用来暂存运行状态1/2的每位bit值

			--依次读入上传的数据
			for i=1,(templen-7)/2,1 do
				packet[ status_cmds[i] ] = bit.lshift( getnumber(10+i*2) , 8 ) + getnumber(11+i*2)
			end

			--[[
			--将上传的数据转化为JSON格式数据 上传协议中前5个状态寄存器数据
			packet[ status_cmds[1] ] = databuff_table[1]/100
			packet[ status_cmds[2] ] = databuff_table[2]-20
			packet[ status_cmds[3] ] = databuff_table[3]
			packet[ status_cmds[4] ] = databuff_table[4]
			packet[ status_cmds[5] ] = databuff_table[5]/10
			--]]
			--[[
			--解析运行状态1(对应高字节databuff_table[26],低字节databuff_table[27])的每个bit位值
			for i=0,1,1 do --两个字节
				for j=1,8,1 do
					-- j-1的意思是，由于j从1开始，但是移位操作应该从1左移0位，所以减一
					bitbuff_table[i*2+j] = bit.band(databuff_table[27-i],bit.lshift(1,j-1))
				end
			end
			--将运行状态1的每位bit值转化为JSON格式数据
			packet[ status_cmds[11] ] = bitbuff_table[1]
			packet[ status_cmds[12] ] = bitbuff_table[2]
			packet[ status_cmds[13] ] = bitbuff_table[4]
			packet[ status_cmds[14] ] = bitbuff_table[5]
			packet[ status_cmds[15] ] = bitbuff_table[6]
			packet[ status_cmds[16] ] = bitbuff_table[7]
			packet[ status_cmds[17] ] = bitbuff_table[8]
			packet[ status_cmds[18] ] = bitbuff_table[9]
			packet[ status_cmds[19] ] = bitbuff_table[10]
			packet[ status_cmds[20] ] = bitbuff_table[15]
			packet[ status_cmds[21] ] = bitbuff_table[16]

			--解析运行状态2(对应高字节databuff_table[28],低字节databuff_table[29])的每个bit位值
			for i=0,1,1 do --两个字节
				for j=1,8,1 do
					-- j-1的意思是，由于j从1开始，但是移位操作应该从1左移0位，所以减一
					bitbuff_table[i*2+j] = bit.band(databuff_table[29-i],bit.lshift(1,j-1))
				end
			end
			--将运行状态2的每位bit值转化为JSON格式数据
			packet[ status_cmds[22] ] = bitbuff_table[1]
			packet[ status_cmds[23] ] = bitbuff_table[2]
			packet[ status_cmds[24] ] = bitbuff_table[4]
			packet[ status_cmds[25] ] = bitbuff_table[5]
			packet[ status_cmds[26] ] = bitbuff_table[6]
			packet[ status_cmds[27] ] = bitbuff_table[7]
			packet[ status_cmds[28] ] = bitbuff_table[8]
			packet[ status_cmds[29] ] = bitbuff_table[9]
			packet[ status_cmds[30] ] = bitbuff_table[14]
			packet[ status_cmds[31] ] = bitbuff_table[15]
			packet[ status_cmds[32] ] = bitbuff_table[16]
		--]]

		end

	else
		packet['head_error'] = 'error'
	end

	return Json(packet)
end

return _M
