local shared = require("modules/filebrowser/patches/home/widgets/strip_common")

return {
    id = "strip_tbr",
    label = "To Be Read strip widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "to_be_read")
    end,
}
