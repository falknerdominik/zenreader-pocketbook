local shared = require("modules/filebrowser/patches/home/widgets/strip_common")

return {
    id = "strip_custom",
    label = "Custom strip widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "custom_strip")
    end,
}
