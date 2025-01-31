--[[
Title: MC Main Login Procedure
Author(s):  LiPeng, LiXizhi
Company: ParaEngine
Date: 2014.9.14
Desc: 
use the lib:
------------------------------------------------------------
NPL.load("(gl)script/mobile/paracraft/Login/MainLogin.lua");
ParaCraft.Mobile.MainLogin:start();
------------------------------------------------------------
]]
local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic")

-- create class
local MainLogin = commonlib.gettable("ParaCraft.Mobile.MainLogin");
local UserLoginProcess = nil;

-- the initial states in the state machine. 
-- Please see self:next_step() for more information on the meaning of these states. 
MainLogin.state = {
	HasGotVersionInfo = nil,
	CheckGraphicsSettings = nil,
	Loaded3DScene = nil,
	IsLoginModeSelected = nil,
	IsPluginLoaded = nil,
	HasSignedIn = nil,
	HasInitedTexture = nil,
		IsRegistrationRequested = nil,
		IsUserSelected = nil,
		IsLoginStarted = nil,
		IsOfflineModeActivated =nil,
		IsRegRealnm = false,
		IsRestGatewayConnected = nil,
		IsProductVersionVerified = nil,
		IsUserNidSelected = nil,
		IsRegUserRequested = nil,
		IsRegUserConfirmRequested = nil,
		IsAuthenticated = nil,
		IsNickNameVerified = nil,
		IsAvatarCreationRequested = nil,
		IsFamilyInfoVerified = nil,
		IsGlobalStoreSynced = nil,
		IsExtendedCostSynced = nil,
		IsInventoryVerified = nil,
		IsEssentialItemsVerified = nil,
		IsPetVerified = nil,
		IsVIPItemsVerified = nil,
		IsFriendsVerified = nil,
		IsJabberInited = nil,	
		IsCleanCached = nil,
	IsLoadMainWorldRequested = nil,
	IsCreateNewWorldRequested = nil,
	IsLoadTutorialWorldRequested = nil, -- NOT used

	-- table of {user_nid = "1234567", user_name = "", password="",}, as a result of SelectLocalUser
	local_user = nil,	
	-- the background 3d world path during login. This is set during Updater progress. We can display some news and movies in it. 
	login_bg_worldpath = nil,
	-- a table of {username, password} as a result of UserLoginPage
	auth_user = nil,
	-- registration user
	reg_user = {},
	-- a table of {worldpath, role, bHideProgressUI, movie, gs_nid, ws_id }, to be passed to LoadWorld command. 
	-- where gs_nid is the game server nid, and ws_id is the world server id. 
	load_world_params = nil,
	-- the main login world
	login_bg_worldpath = nil,
	-- the preferred gateway game server during login process. nil or a table of {nid=game_server_nid_string}
	gateway_server = nil,
};

-- mapping from game server nid to last ping latency in milliseconds
MainLogin.network_latency = {};

-- start the login procedure. Only call this function once. 
-- @param init_callback: the one time init function to be called to load theme and config etc.
function MainLogin:start(init_callback)
	-- initial states
	MainLogin.state = {
		reg_user = {},
	};
	self.init_callback = init_callback;

	
	NPL.load("(gl)script/apps/Aries/Creator/Game/mcml/pe_mc_mcml.lua");
	MyCompany.Aries.Game.mcml_controls.register_all();

	NPL.load("(gl)script/apps/Aries/Creator/Game/Login/UserLoginProcess.lua");
	UserLoginProcess = UserLoginProcess or commonlib.gettable("MyCompany.Aries.Game.UserLoginProcess");


	-- register external functions for each login step. Each handler's first parameter is MainLogin class instance. 
	-- TODO: add your custom handlers here. 
	self.handlers = self.handlers or {
		-- get version info
		HasGotVersionInfo = self.GetVersionInfo,
		-- check for graphics settings
		CheckGraphicsSettings = self.CheckGraphicsSettings,
		-- load the background 3d scene
		LoadBackground3DScene = self.LoadBackground3DScene,
		-- load all modules/plugins
		LoadPlugins = self.LoadPlugins,
		-- select local or internet game
		LoadPackages = self.LoadPackages,		
		-- select local or internet game
		ShowLoginModePage = self.ShowLoginModePage,

		HasInitedTexture = self.HasInitedTexture,

		-- login page
		UserLoginProcess = self.Proc_UserLoginProcess,
			-- access token should already be passed to us command line
			ExternalUserSignIn = UserLoginProcess.Proc_ExternalUserSignIn,
			-- establish the first rest connection with the initial gateway game server. 
			ConnectRestGateway = UserLoginProcess.Proc_ConnectRestGateway,
			-- Establish connection with the default gateway game server; and authenticate the user and establish jabber connection. 
			AuthUser = UserLoginProcess.Proc_Authentication,
			-- verify product version
			VerifyProductVersion = UserLoginProcess.Proc_VerifyProductVersion,
			-- select user nid
			SelectUserNid = UserLoginProcess.SelectUserNid,
			-- if AuthUser returns msg.isreg is false, we will needs to trigger this one before proceding to next step. 
			CreateNewAvatar = UserLoginProcess.CreateNewAvatar,
			-- note:if no nick name is found, this user should be treated as a newly registered user, 
			-- and we should direct it to CreateNewAvatar page
			VerifyNickName = UserLoginProcess.Proc_VerifyNickName,
			-- download the family profile 
			VerifyFamilyInfo = UserLoginProcess.Proc_VerifyFamilyInfo,
			-- verify all server objects
			VerifyServerObjects = UserLoginProcess.Proc_VerifyServerObjects,
			-- sync global store
			SyncGlobalStore = UserLoginProcess.Proc_SyncGlobalStore,
			-- sync extended cost template
			ExtendedCostTemplate = UserLoginProcess.Proc_SyncExtendedCost,
			-- verify the inventory 
			VerifyInventory = UserLoginProcess.Proc_VerifyInventory,
			-- verify pet
			VerifyPet = UserLoginProcess.Proc_VerifyPet,
			-- verify essential items
			VerifyEssentialItems = UserLoginProcess.Proc_VerifyEssentialItems,
			-- verify vip items
			VerifyVIPItems = UserLoginProcess.Proc_VerifyVIPItems,
			-- verify friends
			VerifyFriends = UserLoginProcess.Proc_VerifyFriends,
			-- init jabber
			InitJabber = UserLoginProcess.Proc_InitJabber,
			-- Clean Cache
			CleanCache = UserLoginProcess.Proc_CleanCache,
			-- pick a world server
			SelectWorldServer = UserLoginProcess.Proc_SelectWorldServer,
			
		-- connect main world
		LoadMainWorld = self.LoadMainWorld,
		-- create new world
		ShowCreateWorldPage = self.ShowCreateWorldPage,
	}

	
	self:next_step();

end

-- invoke a handler 
function MainLogin:Invoke_handler(handler_name)
	if(self.handlers and self.handlers[handler_name]) then
		LOG.std("", "system","Login", "=====>Login Stage: %s", handler_name);
		self.handlers[handler_name](self);
	else
		LOG.std("", "error","Login", "error: unable to find login handler %s", handler_name);
	end
end

-- perform next step. 
-- @param state_update: This can be nil, it is a table to modify the current state. such as {IsLocalUserSelected=true}
function MainLogin:next_step(state_update)

	--print("1111111111111111111111")

	local state = self.state;
	if(state_update) then
	
		--print("2222222222222222")
	
		commonlib.partialcopy(state, state_update);
		
		--print("3333333333333")

		if(not state.IsLoginModeSelected) then
			state.HasSignedIn = false;
		end
		
		--print("4444444444444")
	end
	if(not state.IsInitFuncCalled) then
		if(self.init_callback) then
			--print("55555555555555")
			self.init_callback();
			--print("66666666666666666")
		end

		System.options.version = "kids";
		if(not System.options.mc) then
			NPL.load("(gl)script/apps/Aries/Login/ExternalUserModule.lua");
			local ExternalUserModule = commonlib.gettable("MyCompany.Aries.ExternalUserModule");
			if(ExternalUserModule.Init) then
				--print("77777777777")
				ExternalUserModule:Init(true);
				--print("888888888888888")
			end
		end
		--print("999999999999999")
		NPL.load("(gl)script/apps/Aries/Creator/Game/game_logic.lua");
		self:next_step({IsInitFuncCalled = true});
		--print("aaaaaaaaaaaaaaaaaaaa")
	elseif(not state.HasGotVersionInfo) then
		--print("bbbbbbbbbbbbbbbbb")
		self:GetVersionInfo();
		--print("cccccccccccccccc")
	elseif(not state.CheckGraphicsSettings) then
		--print("ddddddddddddddd")
		self:Invoke_handler("CheckGraphicsSettings");
		--print("eeeeeeeeeeeeee")
	elseif(not state.Loaded3DScene) then
		if(not System.options.isAB_SDK) then
			-- uncomment to enable 3d bg scene during login
			-- state.login_bg_worldpath = "worlds/DesignHouse/CreatorLoginBG";
		end

		--print("ffffffffffffffffff")
		self:Invoke_handler("LoadBackground3DScene");
		--print("fffffffffffffffff@@@@@@@@@@@@")
	elseif(not state.IsPackagesLoaded) then
		--print("ggggggggggggggg")
		self:Invoke_handler("LoadPackages");
		--print("hhhhhhhhhhhh")
	elseif(not state.IsLoginModeSelected) then
		--print("iiiiiiiiiiiiii")
		self:Invoke_handler("ShowLoginModePage");
		--print("jjjjjjjjjjjjjjjjjjjjj")
	--elseif(not state.HasSignedIn) then
		---- not signed in 
		--self:Handle_UserLoginProcess();
	elseif(not state.IsPluginLoaded) then
		--print("kkkkkkkkkkkkkkkkkkk")
		self:Invoke_handler("LoadPlugins");
		--print("LLLLLLLLLLLLLLLLL")

	elseif(not state.HasInitedTexture) then
		--print("mmmmmmmmmmmmmmmmmmmmm")
		self:Invoke_handler("HasInitedTexture");
		--print("nnnnnnnnnnnnnnnnnnnnnn")
	else
		-- already signed in 
		if(not state.IsLoadMainWorldRequested) then	
			--print("oooooooooooooooooooo")
			self:Invoke_handler("LoadMainWorld");
			--print("pppppppppppppppppppppp")
		-- don't load the exsiting world ,can call   [[self:Invoke_handler("ShowCreateWorldPage")]]    enter the create new world page
		elseif(not state.IsCreateNewWorldRequested) then	
		--print("qqqqqqqqqqqqqqqqqqq")
			self:Invoke_handler("ShowCreateWorldPage");
			--print("rrrrrrrrrrrrrrrrrrr")
		end
	end
end

function MainLogin:GetVersionInfo()
	NPL.load("(gl)script/mobile/paracraft/Login/VersionUpdate.lua");
	local VersionUpdate = commonlib.gettable("ParaCraft.Mobile.Login.VersionUpdate");
	VersionUpdate.OnInit(function ()
		--MainLogin:next_step({HasGotVersionInfo = true});
	end);
	MainLogin:next_step({HasGotVersionInfo = true});
end

function MainLogin:CheckGraphicsSettings()
	if(System.options.mc) then
		MainLogin:next_step({CheckGraphicsSettings = true});
		return;
	end
	-- check for graphics settings, this step is moved here so that it will show up in web browser as well.
	NPL.load("(gl)script/apps/Aries/Desktop/AriesSettingsPage.lua");
	MyCompany.Aries.Desktop.AriesSettingsPage.CheckMinimumSystemRequirement(true, function(result, sMsg)
		if(result >=0 ) then
			self:AutoAdjustGraphicsSettings();
		else
			-- exit because PC is too old. 
		end
	end);
end 

function MainLogin:AutoAdjustGraphicsSettings()
	if(System.options.mc) then
		MainLogin:next_step({CheckGraphicsSettings = true});
		return;
	end
	MyCompany.Aries.Desktop.AriesSettingsPage.AutoAdjustGraphicsSettings(false, 
		function(bChanged) 
			if(ParaEngine.GetAttributeObject():GetField("HasNewConfig", false)) then
				ParaEngine.GetAttributeObject():SetField("HasNewConfig", false);
				_guihelper.MessageBox("您上次运行时更改了图形设置. 是否保存目前的显示设置.", function(res)	
					if(res and res == _guihelper.DialogResult.Yes) then
						-- pressed YES
						ParaEngine.WriteConfigFile("config/config.txt");
					end
					MainLogin:next_step({CheckGraphicsSettings = true});
				end, _guihelper.MessageBoxButtons.YesNo)
			else
				MainLogin:next_step({CheckGraphicsSettings = true});
			end
		end,
		-- OnChangeCallback, return false if you want to dicard the changes. 
		function(params)
			if(System.options.IsWebBrowser) then
				if(params.new_effect_level) then
					MyCompany.Aries.Desktop.AriesSettingsPage.AdjustGraphicsSettingsByEffectLevel(params.new_effect_level)
				end
				if(params.new_screen_resolution) then
					local x,y = params.new_screen_resolution[1], params.new_screen_resolution[2];
					if(x == 800) then  x = 720 end
					if(y == 533) then y = 480 end
					commonlib.log("ask web browser host to change resolution to %dx%d\n", x,y);
					commonlib.app_ipc.ActivateHostApp("change_resolution", nil, x, y);
				end
				return false;
			end
		end);
end

-- trap some global event to enable debugging on startup
function MainLogin:HookEventHandler()
	local hookType = CommonCtrl.os.hook.HookType.WH_CALLWNDPROC;
	CommonCtrl.os.hook.SetWindowsHook({hookType=hookType, callback = function()
		local dik_key = VirtualKeyToScaneCodeStr[virtual_key];
		local ctrl_pressed = ParaUI.IsKeyPressed(DIK_SCANCODE.DIK_LCONTROL) or ParaUI.IsKeyPressed(DIK_SCANCODE.DIK_RCONTROL);
		if(dik_key == "DIK_F12") then
			Map3DSystem.App.Commands.Call("Help.Debug");
		elseif(dik_key == "DIK_F3" and ctrl_pressed) then
			Map3DSystem.App.Commands.Call("File.MCMLBrowser");
		end
	end, 
	hookName = "mc_login_keydown", appName="input", wndName = "key_down"});
end

function MainLogin:UnhookEventHandler()
	local hookType = CommonCtrl.os.hook.HookType.WH_CALLWNDPROC;
	CommonCtrl.os.hook.UnhookWindowsHook({hookName = "mc_login_keydown", hookType = hookType});
end

-- login handler
function MainLogin:LoadBackground3DScene()

	--print("1111111111111111111")

	ParaEngine.SetWindowText(string.format("%s -- ver %s", L"创意空间 ParaCraft", GameLogic.options.GetClientVersion()));

	--print("222222222222222222222")
	
	self:HookEventHandler();
	
	--print("333333333333333333333")

	-- always disable AA for mc. 
	if(ParaEngine.GetAttributeObject():GetField("MultiSampleType", 0)~=0) then
	
		--print("44444444444444")
		ParaEngine.GetAttributeObject():SetField("MultiSampleType", 0);
		--print("555555555555555555")
		LOG.std(nil, "info", "FancyV1", "MultiSampleType must be 0 in order to use deferred shading. We have set it for you. you must restart. ");
		ParaEngine.WriteConfigFile("config/config.txt");
		
		--print("66666666666666666")
	end

	local FancyV1 = GameLogic.GetShaderManager():GetFancyShader();
	
	--print("7777777777777")
	if(false and FancyV1.IsHardwareSupported()) then
	--print("888888888888888")
		GameLogic.GetShaderManager():SetShaders(2);
		--print("9999999999999999")
		GameLogic.GetShaderManager():SetUse3DGreyBlur(true);
		--print("aaaaaaaaaaaaa")
	end

	if(self.state.login_bg_worldpath) then
		local world
		
		Map3DSystem.UI.LoadWorld.LoadWorldImmediate(self.state.login_bg_worldpath, true, true, function(percent)
		--print("bbbbbbbbbbbbbbbbbbb")
				if(percent == 100) then
					local worldpath = ParaWorld.GetWorldDirectory();
					--print("ccccccccccccccccc")
					-- leave previous block world.
					ParaTerrain.LeaveBlockWorld();
					--print("dddddddddddddddddddd")

					if(commonlib.getfield("MyCompany.Aries.Game.is_started")) then
					--print("eeeeeeeeeeeeeeeeee")
						-- if the MC block world is started before, exit it. 
						NPL.load("(gl)script/apps/Aries/Creator/Game/main.lua");
						local Game = commonlib.gettable("MyCompany.Aries.Game")
						--print("ffffffffffffffff")
						Game.Exit();
						--print("ggggggggggggggggg")
					end
						--print("hhhhhhhhhhhhhhhh")
					-- we will load blocks if exist. 
					if(	ParaIO.DoesAssetFileExist(format("%sblockWorld.lastsave/blockTemplate.xml", worldpath), true) or
						ParaIO.DoesAssetFileExist(format("%sblockWorld/blockTemplate.xml", worldpath), true) ) then	
						--print("iiiiiiiiiiiiiiiiii")
						NPL.load("(gl)script/apps/Aries/Creator/Game/game_logic.lua");
						local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic")
						GameLogic.StaticInit(1);
						--print("jjjjjjjjjjjjjjjjjjjjjj")
					end
					--print("kkkkkkkkkkkkkkkkkk")
					-- block user input
					ParaScene.GetAttributeObject():SetField("BlockInput", true);
					--print("LLLLLLLLLLLLL")
					--ParaCamera.GetAttributeObject():SetField("BlockInput", true);

					-- MyCompany.Aries.WorldManager:PushWorldEffectStates({ bUseShadow = true, bFullScreenGlow=true})

					-- replace main character with dummy
					local player = ParaScene.GetPlayer();
					--print("mmmmmmmmmmmmmmm")
					player:ToCharacter():ResetBaseModel(ParaAsset.LoadParaX("", ""));
					--print("nnnnnnnnnnnnnnnnnn")
					player:SetDensity(0); -- make it flow in the air
					--print("oooooooooooooooo")
					--ParaScene.GetAttributeObject():SetField("ShowMainPlayer", false);
				end
			end)
	else
		--print("pppppppppppppp")
		self:ShowLoginBackgroundPage(true, true, true, true);
		--print("rrrrrrrrrrrrrrrrr")
	end	
	--print("ssssssssssssssssssss")
	self:next_step({Loaded3DScene = true});
	--print("ttttttttttttttttt")
end

function MainLogin:HasInitedTexture()
	NPL.load("(gl)script/apps/Aries/Creator/Game/Areas/TextureModPage.lua");
	local TextureModPage = commonlib.gettable("MyCompany.Aries.Creator.Game.Desktop.TextureModPage");

	TextureModPage.OnInitDS()
	self:next_step({HasInitedTexture = true});
end

-- handles local or internet user login. 
function MainLogin:Handle_UserLoginProcess()
	if(System.options.loginmode == "local") then
		-- this is just a silent step to perform local sign in
		self:next_step({HasSignedIn = true});

	elseif(System.options.loginmode == "internet") then
		-- for internet
		local state = self.state;
		if(not state.IsExternalUserSignedIn) then
			self:Invoke_handler("ExternalUserSignIn");	
		elseif(not state.IsRestGatewayConnected) then
			self:Invoke_handler("ConnectRestGateway");	
		elseif(not state.IsProductVersionVerified) then
			self:Invoke_handler("VerifyProductVersion");	
		elseif(not state.IsUserNidSelected) then
			self:Invoke_handler("SelectUserNid");	
		elseif(state.IsRegUserRequested) then		
			self:Invoke_handler("RegUser");	
		elseif(state.IsRegUserConfirmRequested) then		
			self:Invoke_handler("RegUserConfirm");	
		elseif(not state.IsAuthenticated) then	
			self:Invoke_handler("AuthUser");
		elseif(not state.IsFriendsVerified) then
			self:Invoke_handler("VerifyFriends");		
		elseif(not state.IsGlobalStoreSynced) then
			self:Invoke_handler("SyncGlobalStore"); -- move the sync global store process before create avatar
		elseif(not state.IsExtendedCostSynced) then
			self:Invoke_handler("ExtendedCostTemplate");
		elseif(not state.IsAvatarCreationRequested) then		
			self:Invoke_handler("CreateNewAvatar");
		elseif(not state.IsNickNameVerified) then
			self:Invoke_handler("VerifyNickName");
		elseif(not state.IsFamilyInfoVerified) then	
			self:Invoke_handler("VerifyFamilyInfo");
		elseif(not state.IsServerObjectsVerified) then	
			self:Invoke_handler("VerifyServerObjects");
		elseif(not state.IsInventoryVerified) then
			self:Invoke_handler("VerifyInventory");	
		elseif(not state.IsEssentialItemsVerified) then
			self:Invoke_handler("VerifyEssentialItems");
		elseif(not state.IsPetVerified) then
			self:Invoke_handler("VerifyPet");
		elseif(not state.IsVIPItemsVerified) then
			self:Invoke_handler("VerifyVIPItems");
		elseif(not state.IsCleanCached) then
			self:Invoke_handler("CleanCache");
		elseif(not state.IsJabberInited) then
			self:Invoke_handler("InitJabber");
		elseif(not state.IsWorldServerSelected) then
			self:Invoke_handler("SelectWorldServer");
		else
			_guihelper.CloseMessageBox();
			System.User.isOnline = true;
			self:next_step({HasSignedIn = true});
		end
	end
end

-- handles local or internet user login. 
function MainLogin:user_login_next_step(state_update)
	if(MainLogin.connect_server) then
		self:connect_server_next_step(state_update)
		return;
	end

	local state = self.state;
	if(state_update) then
		commonlib.partialcopy(state, state_update);
	end
	if(not state.IsExternalUserSignedIn) then
		self:Invoke_handler("ExternalUserSignIn");	
	elseif(not state.IsRestGatewayConnected) then
		self:Invoke_handler("ConnectRestGateway");	
	elseif(not state.IsProductVersionVerified) then
		self:Invoke_handler("VerifyProductVersion");	
	elseif(not state.IsUserNidSelected) then
		self:Invoke_handler("SelectUserNid");	
	elseif(state.IsRegUserRequested) then		
		self:Invoke_handler("RegUser");	
	elseif(state.IsRegUserConfirmRequested) then		
		self:Invoke_handler("RegUserConfirm");	
	elseif(not state.IsAuthenticated) then	
		self:Invoke_handler("AuthUser");
	elseif(not state.IsFriendsVerified) then
		self:Invoke_handler("VerifyFriends");		
	elseif(not state.IsGlobalStoreSynced) then
		self:Invoke_handler("SyncGlobalStore"); -- move the sync global store process before create avatar
	elseif(not state.IsExtendedCostSynced) then
		self:Invoke_handler("ExtendedCostTemplate");
	elseif(not state.IsAvatarCreationRequested) then		
		self:Invoke_handler("CreateNewAvatar");
	elseif(not state.IsNickNameVerified) then
		self:Invoke_handler("VerifyNickName");
	elseif(not state.IsFamilyInfoVerified) then	
		self:Invoke_handler("VerifyFamilyInfo");
	elseif(not state.IsServerObjectsVerified) then	
		self:Invoke_handler("VerifyServerObjects");
	elseif(not state.IsInventoryVerified) then
		self:Invoke_handler("VerifyInventory");	
	elseif(not state.IsEssentialItemsVerified) then
		self:Invoke_handler("VerifyEssentialItems");
	elseif(not state.IsPetVerified) then
		self:Invoke_handler("VerifyPet");
	elseif(not state.IsVIPItemsVerified) then
		self:Invoke_handler("VerifyVIPItems");
	elseif(not state.IsCleanCached) then
		self:Invoke_handler("CleanCache");
	elseif(not state.IsJabberInited) then
		self:Invoke_handler("InitJabber");
	elseif(not state.IsWorldServerSelected) then
		self:Invoke_handler("SelectWorldServer");
	else
		_guihelper.CloseMessageBox();
		System.User.isOnline = true;
		MainLogin:LoadMainWorld();
		--self:next_step({HasSignedIn = true});
	end
end

function MainLogin:connect_server_next_step(state_update)
	local state = self.state;
	if(state_update) then
		commonlib.partialcopy(state, state_update);
	end
	if(not state.IsRestGatewayConnected) then
		self:Invoke_handler("ConnectRestGateway");	
	elseif(not state.IsProductVersionVerified) then
		self:Invoke_handler("VerifyProductVersion");
	else
		--_guihelper.CloseMessageBox();
		MainLogin.connect_server = false;
		System.User.internet_ip = System.User.internet_ip or true;
		--self:next_step({HasSignedIn = true});
	end
end

-- handles local or internet user login. 
function MainLogin:reset_user_login_steps()
	local state_update = {
		IsExternalUserSignedIn = nil,
		IsRestGatewayConnected = nil,
		IsProductVersionVerified = nil,
		IsUserNidSelected = nil,
		IsAuthenticated = nil,
		IsFriendsVerified = nil,
		IsGlobalStoreSynced = nil,
		IsExtendedCostSynced = nil,
		IsNickNameVerified = nil,
		IsFamilyInfoVerified = nil,
		IsServerObjectsVerified = nil,
		IsInventoryVerified = nil,
		IsEssentialItemsVerified = nil,
		IsPetVerified = nil,
		IsVIPItemsVerified = nil,
		IsCleanCached = nil,
		IsJabberInited = nil,
		IsWorldServerSelected = nil,
	};
	local state = self.state;
	commonlib.partialcopy(state, state_update);
	System.options.loginmode = "local";
end

-- load predefined mod packages if any
function MainLogin:LoadPackages()
	NPL.load("(gl)script/apps/Aries/Creator/Game/Login/BuildinMod.lua");
	local BuildinMod = commonlib.gettable("MyCompany.Aries.Game.MainLogin.BuildinMod");
	BuildinMod.AddBuildinMods();

	self:next_step({IsPackagesLoaded = true});
end

function MainLogin:ShowLoginModePage()
	if(System.options.cmdline_world and System.options.cmdline_world~="") then
		System.options.loginmode = "local";
		self:next_step({IsLoginModeSelected = true});
		return;
	end

	System.App.Commands.Call("File.MCMLWindowFrame", {
		url = "script/mobile/paracraft/Login/SelectLoginModePage.html", 
		name = "ShowLoginModePage", 
		isShowTitleBar = false,
		DestroyOnClose = true, -- prevent many ViewProfile pages staying in memory
		style = CommonCtrl.WindowFrame.ContainerStyle,
		zorder = 0,
		allowDrag = false,
		directPosition = true,
			align = "_fi",
			x = 0,
			y = 0,
			width = 0,
			height = 0,
		cancelShowAnimation = true,
	});
end

function MainLogin:LoadPlugins()
	NPL.load("(gl)script/apps/Aries/Creator/Game/game_logic.lua");
    local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic")
    GameLogic.InitMod();
	self:next_step({IsPluginLoaded = true});
end

-- return true if loaded
function MainLogin:CheckLoadWorldFromCmdLine()
	local worldpath = System.options.cmdline_world;
	if(worldpath and worldpath~="" and not self.cmdWorldLoaded) then
		self.cmdWorldLoaded = true;
		NPL.load("(gl)script/apps/Aries/Creator/WorldCommon.lua");
		local WorldCommon = commonlib.gettable("MyCompany.Aries.Creator.WorldCommon")
		WorldCommon.OpenWorld(worldpath, true);
		return true;
	end
end

function MainLogin:LoadMainWorld()
	self:UnhookEventHandler();

	if(self:CheckLoadWorldFromCmdLine()) then
		return;
	end
	if(System.options.loginmode == "internet") then
		NPL.load("(gl)script/mobile/paracraft/Login/InternetLoadWorld.lua");
		local InternetLoadWorld = commonlib.gettable("ParaCraft.Mobile.Login.InternetLoadWorld");
		InternetLoadWorld.ShowPage();
	elseif(System.options.loginmode == "local") then
		NPL.load("(gl)script/mobile/paracraft/Login/LocalLoadWorld.lua");
		local LocalLoadWorld = commonlib.gettable("ParaCraft.Mobile.Login.LocalLoadWorld")
		LocalLoadWorld.ShowPage()
	end
end

function MainLogin:ShowCreateWorldPage()
	NPL.load("(gl)script/mobile/paracraft/Login/CreateNewWorld.lua");
	local CreateNewWorld = commonlib.gettable("ParaCraft.Mobile.Login.CreateNewWorld")
	CreateNewWorld.ShowPage()
end

function MainLogin:OnSolveNetworkIssue()
end

function MainLogin:ShowLoginBackgroundPage(bShow, bShowCopyRight, bShowLogo, bShowBg)
	local url = "script/mobile/paracraft/Login/LoginBackgroundPage.html?"
	if(bShow) then
		if(bShowCopyRight) then
			url = url.."showcopyright=true&";
		end
		if(bShowLogo) then
			url = url.."showtoplogo=true&";
		end
		if(not self.state.login_bg_worldpath and bShowBg==false) then
			url = url.."showbg=false&";
		end
	end
	System.App.Commands.Call("File.MCMLWindowFrame", {
		url = url, 
		name = "LoginBGPage", 
		isShowTitleBar = false,
		DestroyOnClose = true, -- prevent many ViewProfile pages staying in memory
		style = CommonCtrl.WindowFrame.ContainerStyle,
		allowDrag = false,
		zorder = -2,
		bShow = bShow,
		directPosition = true,
			align = "_fi",
			x = 0,
			y = 0,
			width = 0,
			height = 0,
		cancelShowAnimation = true,
	});
end