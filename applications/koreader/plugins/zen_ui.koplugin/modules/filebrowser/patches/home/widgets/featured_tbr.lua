local shared = require("modules/filebrowser/patches/home/widgets/featured_common")

return {
    id = "featured_tbr",
    label = "To Be Read featured widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx, "to_be_read")
    end,
}
