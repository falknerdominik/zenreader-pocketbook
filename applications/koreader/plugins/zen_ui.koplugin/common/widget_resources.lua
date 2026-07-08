local M = {}

function M.free(widget)
    if widget and widget.free then
        pcall(function() widget:free() end)
    end
end

function M.freeAll(resources)
    if type(resources) ~= "table" then return end
    for _i, widget in ipairs(resources) do
        M.free(widget)
        resources[_i] = nil
    end
end

function M.replaceChild(container, index, widget)
    if not container or not index then return end
    local old_widget = container[index]
    if old_widget and not rawequal(old_widget, widget) then
        M.free(old_widget)
    end
    container[index] = widget
    container.dimen = nil
    if container.resetLayout then
        container:resetLayout()
    end
end

function M.managedPaintWidget(opts)
    opts = opts or {}
    local resources = opts.resources or {}
    return {
        dimen = opts.dimen,
        getSize = opts.getSize or function(self)
            return self.dimen
        end,
        handleEvent = opts.handleEvent or function()
            return false
        end,
        paintTo = opts.paintTo,
        free = function()
            M.freeAll(resources)
            if opts.free then pcall(opts.free) end
        end,
    }
end

function M.wrapFree(widget, free_func)
    if not widget or type(free_func) ~= "function" then return end
    local orig_free = widget.free
    widget.free = function(self, ...)
        free_func()
        if orig_free then
            return orig_free(self, ...)
        end
    end
end

return M
