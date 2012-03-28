module Heroku
  module Helpers

    def style_warning(message)
      hputs("  ~ #{message}")
    end

    def style_action(action)
      hprint("* #{action} ")
    end

    def style_info(info)
      hputs("+ #{info}: ")
    end

    def style_object(object)
      case object
      when Array
        object.sort.each do |item|
          hputs("  - #{item}")
        end
      when Hash
        object.keys.sort_by {|key| key.to_s}.each do |key|
          hprint("  = #{key}: ")
          case data = object[key]
          when Array
            hputs
            data.sort.each do |item|
              hputs("    - #{item}")
            end
          when Hash
            hputs
            data.keys.sort_by {|key| key.to_s}.each do |key|
              hputs("    = #{key}: #{data[key]}")
            end
          else
            hputs("#{data}")
          end
        end
      else
        hputs(object.to_s)
      end
    end

  end
end
