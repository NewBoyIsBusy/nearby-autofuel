name = "附近自动添燃料（不浪费）"
description = [[建筑缺燃料时，自动取用附近箱子或地上的燃料。
箱子优先，箱内按槽位顺序；跳过不适用物品。
每次只取一个，剩余容量能完整容纳时才添加。
支持火堆、石头火坑、冷火、暗夜灯、灭火器和薇诺娜发电机等。]]
author = "wanzi"
version = "1.0.1"
-- This package ships loose files, without a Klei-generated modmanifest.
forcemanifest = false
api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
client_only_mod = false
all_clients_require_mod = false
server_only_mod = true
server_filter_tags = { "自动添燃料" }

configuration_options =
{
    {
        name = "SEARCH_RADIUS", label = "取料范围",
        hover = "以建筑为中心的距离；4 距离约为一块地皮宽。",
        options = {
            { description = "4（约1块地皮）", data = 4 },
            { description = "8（约2块地皮）", data = 8 },
            { description = "12（约3块地皮）", data = 12 },
            { description = "16（约4块地皮）", data = 16 },
        }, default = 8,
    },
    {
        name = "REFUEL_PERCENT", label = "开始补充的燃料量",
        hover = "低于或等于该比例才尝试添加；始终要求一份燃料能完整装下。",
        options = {
            { description = "25%", data = 0.25 },
            { description = "50%", data = 0.5 },
            { description = "75%", data = 0.75 },
            { description = "能装下一份就补充", data = 1 },
        }, default = 0.5,
    },
    {
        name = "GROUND_FUEL", label = "取用地面燃料",
        options = {
            { description = "开启（箱子优先）", data = true },
            { description = "关闭（只使用箱子）", data = false },
        }, default = true,
    },
    {
        name = "CHECK_INTERVAL", label = "检查间隔",
        options = {
            { description = "0.5秒", data = 0.5 },
            { description = "1秒", data = 1 },
            { description = "2秒", data = 2 },
        }, default = 0.5,
    },
    {
        name = "REFUEL_EMPTY", label = "给已耗尽的建筑补充",
        hover = "开启后，附近存在合适燃料时会重新点燃空火坑。关闭后只维护尚有燃料的建筑。",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        }, default = true,
    },
}
