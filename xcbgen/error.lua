local ResolveException = {}
ResolveException.__index = ResolveException

function ResolveException.new(message)
    local self = setmetatable({
        message = message or "Resolve error"
    }, ResolveException)
    return self
end

function ResolveException:__tostring()
    return self.message
end
