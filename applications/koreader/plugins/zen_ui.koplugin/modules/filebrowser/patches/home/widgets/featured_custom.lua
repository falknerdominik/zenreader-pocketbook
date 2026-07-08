local shared = require("modules/filebrowser/patches/home/widgets/featured_common")

return {
    id = "featured_custom",
    label = "Custom featured widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx, "custom_featured")
    end,
}
