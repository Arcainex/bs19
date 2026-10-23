-- Every network event name lives here so modules don't hardcode strings.

BS = BS or {}

BS.Events = {
    -- Session lifecycle
    ClientReady          = 'bs:session:clientReady',
    SessionState         = 'bs:session:state',
    Kick                 = 'bs:session:kick',

    -- Characters
    CharactersList       = 'bs:characters:list',
    CharacterCreate      = 'bs:characters:create',
    CharacterDelete      = 'bs:characters:delete',
    CharacterSelect      = 'bs:characters:select',
    CharacterSpawned     = 'bs:characters:spawned',
    CharacterLogout      = 'bs:characters:logout',

    -- Player data replication
    PlayerLoaded         = 'bs:player:loaded',
    PlayerUnloaded       = 'bs:player:unloaded',
    PlayerDataSet        = 'bs:player:dataSet',
    PlayerMoney          = 'bs:player:money',
    PlayerNeeds          = 'bs:player:needs',
    PlayerXP             = 'bs:player:xp',
    PlayerLevelUp        = 'bs:player:levelUp',

    -- Persistence
    RequestSave          = 'bs:player:requestSave',
    UpdatePosition       = 'bs:player:updatePosition',
    UpdateNeeds          = 'bs:player:updateNeeds',
    UpdateOutfit         = 'bs:player:updateOutfit',

    -- UI (implemented by bs_ui)
    UiNotify             = 'bs:ui:notify',
    UiHudState           = 'bs:ui:hudState',
    UiOpen               = 'bs:ui:open',
    UiClose              = 'bs:ui:close',

    -- Callback transport
    CallbackRequest      = 'bs:callback:request',
    CallbackResponse     = 'bs:callback:response',
    CallbackClientReq    = 'bs:callback:clientRequest',
    CallbackClientRes    = 'bs:callback:clientResponse',
}
