name = "Better crafting"
description = "Improves functionality of the crafting menu"
author = "Emi<3"
version = "3.1.0"

forumthread = ""

api_version = 10
priority = 100000000

dont_starve_compatible = false
reign_of_giants_compatible = false
dst_compatible = true

client_only_mod = true
all_clients_require_mod = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

local function Config(label, name, options, default, hover)
    return {label = label, name = name, options = options, default = default, hover = hover or ""}
end

local enableDisableOptions = {{description = "Enabled", data = true}, {description = "Disabled", data = false}}
local function BinaryConfig(label,name,hover)
    return {label = label, name = name, options = enableDisableOptions, default = true, hover = hover or ""}
end

configuration_options = 
{
    BinaryConfig("Use alternate recipes", "useRecipes","Consider alternate recipes for ingredients, like Wilson's transmutation or Woodie's boards, when crafting ingredients"),
    BinaryConfig("Easier hold to craft", "holdToCraft","Continuously craft while holding down the craft button without needing to double click"),
    BinaryConfig("Shorten ingredient names", "shorten","Shorten long ingredient names so that they fit in the button"),
    BinaryConfig("Use skins for ingredients", "useSkins","Use the last used skin for crafted ingredients"),
    BinaryConfig("Unequip ingredients", "unequip","If you have one of the needed ingredients equipped, the button will give you the option to unequip it"),
    BinaryConfig("Always allow crafting ingredients", "alwaysShow","Allow for crafting ingredients even for recipes you don't know yet (this covers up hint text)"),
    BinaryConfig("Display amount crafted", "number","Display the amount of the item crafted from the recipe on the crafting button"),
}