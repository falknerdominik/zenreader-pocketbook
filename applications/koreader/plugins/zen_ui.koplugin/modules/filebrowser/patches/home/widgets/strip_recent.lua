local shared = require("modules/filebrowser/patches/home/widgets/strip_common")

return {
    id = "strip_recent",
    label = "Recently read strip widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "recently_read")
    end,
}
