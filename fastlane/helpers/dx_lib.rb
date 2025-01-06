require 'fastlane'

module DX
  def self.do_retring(attempt_total, &)
    attempt = 1

    while attempt <= attempt_total
      begin
        FastlaneCore::UI.message("Starting attempt #{attempt}/#{attempt_total}")
        yield
        break
      rescue StandardError => e
        FastlaneCore::UI.error("❌ Attempt #{attempt}/#{attempt_total} failed: #{e}")
        attempt += 1
      end
    end

    if attempt > attempt_total
      FastlaneCore::UI.error('❌ Rich attempt limit, see log above')
      return false
    end

    return true
  end
end

class Object
  def _?(x = nil)
    self
  end
end

class NilClass
  def _?(x = nil)
    if block_given?
      yield
    else
      x
    end
  end
end
