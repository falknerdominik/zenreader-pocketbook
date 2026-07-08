local shared = require("modules/filebrowser/patches/home/widgets/featured_common")

return {
    id = "featured",
    label = "Featured widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx)
    end,
}
