local require = GLOBAL.require

require("widgets/widgetutil")
local CraftingMenuDetails = require "widgets/redux/craftingmenu_details"

local OldDoRecipeClick = GLOBAL.DoRecipeClick

--clients lack info on when a crafting attempt ends, 
--so we're introducing some flags for when crafting should be locked
local lock = false
local unlockoverridetime = 0

local function unlock() 
	if unlockoverridetime < GLOBAL.GetTime() then
		lock = false
		unlockoverridetime = -1
	end
end

--crafting animations, used for locking and unlocking
local lockAnims = {
	"build_loop", 
	"construct_loop",
	"carving_loop", 
	"form_log", 
	"wormwood_cast_spawn", 
	"give",
	}

local secondaryLockAnims = {
	"build_pst",
	"construct_pst",
	"useitem_pst",
	"give_pst",
	}

local maxButtonSize = 300

local ingredientNameOverrides = {
	["Opulent Pickaxe"] = "Gold Pick",
	["Feather Pencil"] = "Pencil",
	["Wooden Ball Bobber"] = "Bobber",
	["Compost Wrap"] = "Compost",
	["Trusty Tape"] = "Tape",
	["Beefalo Wool"] = "Beef Wool",
	["Iridescent Gem"] = "Opal Gem",
	["Feathery Canvas"] = "Canvas",
	["Dapper Vest"] = "Vest",
	["Bramble Husk"] = "Husk",
	["Nightmare Fuel"] = "Night Fuel",
	["Clockmaker's Tools"] = "Clock Tools",
	["Gold Nugget"] = "Gold",
	["Waterballoon"] = "Balloon",
	["Pure Brilliance"] = "Brilliance",
	["Electrical Doodad"] = "Doodad",
	["Backtrek Watch"] = "Backtrek",
	["Fashion Goggles"] = "Goggles",
	["Carpeted Flooring"] = "Carpet",
	["Hound's Tooth"] = "Tooth",
	["Healing Salve"] = "Salve",
	["Bone Shards"] = "Bones",
	["Pile o' Balloons"] = "Balloons",
	["Telltale Heart"] = "Heart",
	["Thulecite Medallion"] = "Medallion",
	["Walking Cane"] = "Cane",
	["Bucket-o-poop"] = "Poop Bucket",
	["Thermal Stone"] = "Heat Stone",
}

--keys are products, values are arrays of recipes that craft that product sorted by priority
--priority is currently based on the total number of ingredients used
local recipesByProduct = {}

--creates the recipesByProduct table that makes looking up recipes efficient
AddSimPostInit(
function()
	recipesByProduct = {}
	for name, recipe in pairs(GLOBAL.AllRecipes) do
		if recipesByProduct[recipe.product] == nil then
			recipesByProduct[recipe.product] = {}
		end
		local index = 1
		local newPriority = 0
		if recipe.ingredients ~= nil then
			for i,ingredient in ipairs(recipe.ingredients) do
				if ingredient.type == recipe.product then
					newPriority = math.huge
				end
				newPriority = newPriority + ingredient.amount
			end
		end
		while recipesByProduct[recipe.product][index] ~= nil and newPriority > recipesByProduct[recipe.product][index].priority do
			index = index + 1
		end
		table.insert(recipesByProduct[recipe.product],index,{recipeName = name, priority = newPriority})
    end
end)

AddPlayerPostInit(
	function(inst)
		inst:ListenForEvent("itemget", unlock)
		inst:ListenForEvent("newactiveitem", unlock)
		inst:ListenForEvent("refreshcrafting", unlock)
	end
)

--simple shallow copy
local function copyTable(table)
	local newTable = {}
	for key, value in pairs(table) do
		newTable[key] = value
	end
	return newTable
end

--true if one of the recipe ingredients was already checked
local function ifRepeats(recipe, previouslyChecked)
	for index,ingredient in ipairs(recipe.ingredients) do
		if previouslyChecked[ingredient.type] ~= nil then
			return true
		end
	end
	return false
end

--forward declaration, helper function for findIngredient
local considerRecipe

--recursive function which finds a craftable ingredient
local function findIngredient(owner,recipe,depth,oldPreviouslyChecked)
	if recipe == nil or owner == nil or owner.replica.builder == nil then
		return nil
	end
	local previouslyChecked = copyTable(oldPreviouslyChecked)
	previouslyChecked[recipe.product] = true
	local builderTagCheck = recipe.builder_tag == nil or 
							owner.replica.builder.inst:HasTag(recipe.builder_tag)
	local techCheck = GLOBAL.CanPrototypeRecipe(recipe.level, owner.replica.builder:GetTechTrees())
	local skillTreeCheck = recipe.builder_skill == nil or 
						owner.replica.builder.inst.components.skilltreeupdater:IsActivated(recipe.builder_skill)				
	local canPrototype = 
		techCheck
		and builderTagCheck
		and skillTreeCheck

	local knowsRecipe = owner.replica.builder:KnowsRecipe(recipe)

	--if you can't craft or we get in some weird loop, return
	if depth > 5 or (not knowsRecipe and not canPrototype and not GetModConfigData("alwaysShow")) then
		return nil
	end



	for i, ingredient in ipairs(recipe.ingredients) do
		--check if you already have enough of the ingredient
		local requiredAmount = math.max(1,GLOBAL.RoundBiasedUp(ingredient.amount * owner.replica.builder:IngredientMod()))
		local enoughIngredient = owner.replica.inventory:Has(ingredient.type, requiredAmount, true)
		if not enoughIngredient then
			--look up all recipes for the ingredient and loop through them 
			--(priority based on the number of items in the recipe)
			if GetModConfigData("unequip") and not enoughIngredient and 
			(not owner.replica.inventory:GetActiveItem() or not owner.replica.inventory:IsFull()) then
				for slot, item in pairs(owner.replica.inventory:GetEquips()) do
					if item.prefab == ingredient.type then
						return "unequip", item
					end
				end
			end
			if recipesByProduct[ingredient.type] ~= nil then
				if GetModConfigData("useRecipes") then
					for j,ingredientRecipeArray in ipairs(recipesByProduct[ingredient.type]) do
						local result = {considerRecipe(owner,ingredientRecipeArray.recipeName, previouslyChecked,depth) }
						if result[1] then return GLOBAL.unpack(result) end
					end
				else
					local result = {considerRecipe(owner, ingredient.type, previouslyChecked, depth)}
					if result[1] then return GLOBAL.unpack(result) end
				end
			end
		end
	end
	return nil
end



--returns an ingredient found, or nil if no ingredients in the tree are craftable
considerRecipe = function(owner, name, previouslyChecked, depth)
	local ingredientRecipe = GLOBAL.GetValidRecipe(name)
	if ingredientRecipe ~= nil then
		local can_prototype = 
			GLOBAL.CanPrototypeRecipe(ingredientRecipe.level, owner.replica.builder:GetTechTrees()) 
			and (ingredientRecipe.builder_tag == nil 
				or owner.replica.builder.inst:HasTag(ingredientRecipe.builder_tag))
			and (ingredientRecipe.builder_skill == nil 
				or owner.replica.builder.inst.components.skilltreeupdater:IsActivated(ingredientRecipe.builder_skill))
		local knows_recipe = owner.replica.builder:KnowsRecipe(ingredientRecipe)
		if (knows_recipe or can_prototype) and not ifRepeats(ingredientRecipe,previouslyChecked) then
			--if craftable return, if not then recursive check
			if owner.replica.builder:HasIngredients(ingredientRecipe) then
				return ingredientRecipe
			else
				local result = {findIngredient(owner,ingredientRecipe,depth + 1,previouslyChecked)}
				if result[1] ~= nil then
					return GLOBAL.unpack(result)
				end
			end
		end		
	end
	return nil
end

--unlock crafting if attempting to craft while not in the crafting animation
local function tryUnlock(owner,newRecipe)
	for i,animname in ipairs(lockAnims) do
		if owner.AnimState:IsCurrentAnimation(animname) then
			return
		end
	end
	if owner.replica.inventory:IsFull() and newRecipe and newRecipe.product and 
	  not owner.replica.inventory:Has(newRecipe.product,1,false) then
		for i,animname in ipairs(secondaryLockAnims) do
			if owner.AnimState:IsCurrentAnimation(animname) then
				return
			end
		end
	end
	unlock()
end

--overriding the base function
function GLOBAL.DoRecipeClick(owner, recipe, skin)
	if recipe == nil or 
	  owner == nil or 
	  owner.replica.builder == nil or 
	  owner:HasTag("busy") or 
	  owner.replica.builder:IsBusy() 
	then
		return true
	end

	local buffered = owner.replica.builder:IsBuildBuffered(recipe.name)
    local has_ingredients = buffered or owner.replica.builder:HasIngredients(recipe)

	local result, arg1, arg2 = findIngredient(owner,recipe, 0, {})
	tryUnlock(owner,result)
	if lock then
		return true
	end
	lock = true
	if has_ingredients then
		return OldDoRecipeClick(owner, recipe, skin)
	end
	if result ~= nil then
		if result == "unequip" then
			if unlockoverridetime < 0 then unlockoverridetime = GLOBAL.GetTime() + 0.1 end
			owner.replica.inventory:ControllerUseItemOnSelfFromInvTile(arg1)
			return true
		end
		local skinToUse = 
			GetModConfigData("useSkins") and GLOBAL.Profile:GetLastUsedSkinForItem(result.product) or 
			nil
		return OldDoRecipeClick(owner, result, skinToUse)
	end
	return OldDoRecipeClick(owner,recipe,skin)
end


--unfortunately I had to rewrite the function from scratch, otherwise the vanilla function disables
--the crafting button before this one reenables it, disturbing the hold to craft function

function CraftingMenuDetails:UpdateBuildButton(from_pin_slot)

	--if anyone more knowledgable than me is reading this code and knows how to extract this 
	--local table from widget/redux/craftingmenu_details.lua, please let me know
	local hint_text =
	{
		["NEEDSSCIENCEMACHINE"] = "NEEDSCIENCEMACHINE",
		["NEEDSALCHEMYMACHINE"] = "NEEDALCHEMYENGINE",
		["NEEDSSHADOWMANIPULATOR"] = "NEEDSHADOWMANIPULATOR",
		["NEEDSPRESTIHATITATOR"] = "NEEDPRESTIHATITATOR",
		["NEEDSANCIENTALTAR_HIGH"] = "NEEDSANCIENT_FOUR",
		["NEEDSSPIDERCRAFT"] = "NEEDSSPIDERFRIENDSHIP",
		["NEEDSROBOTMODULECRAFT"] = "NEEDSCREATURESCANNING",
		["NEEDSBOOKCRAFT"] = "NEEDSBOOKSTATION",
		["NEEDSLUNAR_FORGE"] = "NEEDSLUNARFORGING_TWO",
		["NEEDSSHADOW_FORGE"] = "NEEDSSHADOWFORGING_TWO",
		["NEEDSCARPENTRY_STATION"] = "NEEDSCARPENTRY_TWO",
		["NEEDSCARPENTRY_STATION_STONE"] = "NEEDSCARPENTRY_THREE",
		["NEEDSMOONORB_LOW"] = "NEEDSCELESTIAL_ONE",
		["NEEDSMOON_ALTAR_FULL"] = "NEEDSCELESTIAL_THREE",
	}
	

	self.first_sub_ingredient_to_craft = nil

	if self.data == nil then
		return
	end
    local builder = self.owner.replica.builder
	local recipe = self.data.recipe
	local meta = self.data.meta

	

	local teaser = self.build_button_root.teaser
	local button = self.build_button_root.button

	if GetModConfigData("holdToCraft") then
		button:SetOnDown(function()
			button.recipe_held = true
			button.last_recipe_click = nil	
		end)
	end


	local prefix
	local suffix
	local replacementSuffix
	local buttonstr
	local numbersuffix = ""


	if not meta.can_build and recipe.ingredients ~= nil then
		local result, arg1, arg2 = findIngredient(self.owner,recipe,0,{})
		if result == "unequip" then
			local name = GLOBAL.STRINGS.NAMES[string.upper(arg1.prefab)]
			prefix = "Unequip"
			suffix = GetModConfigData("shorten") == true and ingredientNameOverrides[name] or name
			replacementSuffix = "Ingredient"
		else
			self.first_sub_ingredient_to_craft = result
			if result ~= nil then
				local can_prototype = 
					GLOBAL.CanPrototypeRecipe(result.level, self.owner.replica.builder:GetTechTrees()) and 
					not result.nounlock
				local knows_recipe = builder:KnowsRecipe(result)
				local name = GLOBAL.STRINGS.NAMES[string.upper(result.product)]
				prefix = ((can_prototype and not knows_recipe) and GLOBAL.STRINGS.UI.CRAFTING.PROTOTYPE 
							or result.actionstr ~= nil and GLOBAL.STRINGS.UI.CRAFTING.RECIPEACTION[recipe.actionstr] 
							or "Craft")
				suffix = GetModConfigData("shorten") == true and ingredientNameOverrides[name] or name
				if GetModConfigData("number") and result.numtogive ~= 1 then
					numbersuffix = " (x"..result.numtogive..")"
				end
				replacementSuffix = "Ingredient"
			end
		end
	end

	if not buttonstr then
		if prefix and suffix and replacementSuffix then
			buttonstr = prefix .. " " .. suffix..numbersuffix
		else
			buttonstr = meta.build_state == "prototype" and GLOBAL.STRINGS.UI.CRAFTING.PROTOTYPE
						or meta.build_state == "buffered" and GLOBAL.STRINGS.UI.CRAFTING.PLACE
						or recipe.actionstr ~= nil and GLOBAL.STRINGS.UI.CRAFTING.RECIPEACTION[recipe.actionstr]
						or GLOBAL.STRINGS.UI.CRAFTING.BUILD
			if GetModConfigData("number") and recipe.numtogive ~= 1 then
				buttonstr = buttonstr.." (x"..recipe.numtogive..")"
			end
		end
	end 
	

    if not (meta.build_state == "hint" or meta.build_state == "hide" or self.ingredients.hint_tech_ingredient ~= nil) 
	or (GetModConfigData("alwaysShow") and buttonstr) then
        if GLOBAL.TheInput:ControllerAttached() then
            if meta.can_build then
				if from_pin_slot ~= nil and (from_pin_slot.recipe_name ~= recipe.name or self.skins_spinner:GetItem() ~= from_pin_slot.skin_name) then
					teaser:Hide()
				else
					teaser:SetSize(26)
					teaser:UpdateOriginalSize()
					teaser:SetMultilineTruncatedString(GLOBAL.TheInput:GetLocalizedControl(GLOBAL.TheInput:GetControllerID(), GLOBAL.CONTROL_ACCEPT).." "..buttonstr, 2, (self.panel_width / 2) * 0.8, nil, false, true)
					teaser:Show()
				end
            else
				teaser:SetSize(20)
				teaser:UpdateOriginalSize()
				teaser:SetMultilineTruncatedString(self.first_sub_ingredient_to_craft ~= nil and (GLOBAL.TheInput:GetLocalizedControl(GLOBAL.TheInput:GetControllerID(), GLOBAL.CONTROL_ACCEPT).."  "..buttonstr) 
													or meta.build_state == "prototype" and GLOBAL.STRINGS.UI.CRAFTING.NEEDSTUFF_PROTOTYPE
													or GLOBAL.STRINGS.UI.CRAFTING.NEEDSTUFF
													, 2, (self.panel_width / 2) * 0.8, nil, false, true)
				teaser:Show()
            end

			button:Hide()
        else
            button:SetText(buttonstr)
			local w, h = button.text:GetRegionSize()
			button.image:ScaleToSize(GLOBAL.Clamp(w + 50, 145, maxButtonSize), 65)
            if meta.can_build or self.first_sub_ingredient_to_craft or prefix then
                button:Enable()
            else
                button:Disable()
            end

			button:Show()
			teaser:Hide()
        end
    else
		local str
		if self.ingredients.hint_tech_ingredient ~= nil then
			str = GLOBAL.STRINGS.UI.CRAFTING.NEEDSTECH[self.ingredients.hint_tech_ingredient]
		elseif not builder:CanLearn(recipe.name) then
			-- If our recipe's builder tag is a skilltree tag, check if we're the skill tree owner,
			-- and choose a string based on that.
			str = (recipe.builder_tag ~= nil and self.owner.prefab == GLOBAL.TECH_SKILLTREE_BUILDER_TAG_OWNERS[recipe.builder_tag] and STRINGS.UI.CRAFTING.NEEDSCHARACTERSKILL)
				or GLOBAL.STRINGS.UI.CRAFTING.NEEDSCHARACTER
		else
            local prototyper_tree = self:_GetHintTextForRecipe(self.owner, recipe)
            str = GLOBAL.STRINGS.UI.CRAFTING[hint_text[prototyper_tree] or prototyper_tree]
        end
		teaser:SetSize(20)
		teaser:UpdateOriginalSize()
        teaser:SetMultilineTruncatedString(str, 2, (self.panel_width / 2) * 0.8, nil, false, true)

        teaser:Show()
        button:Hide()
    end

end