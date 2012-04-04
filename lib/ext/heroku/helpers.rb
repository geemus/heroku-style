module Heroku
  module Helpers

    def style_warning(message)
      hputs("~~~ #{message}")
    end

    def style_action(action)
      hprint("=== #{action}")
    end

    def style_header(header)
      hputs
      style_info(header)
      hputs
    end

    def style_info(info)
      hputs("=== #{info}")
    end

    def style_object(object)
      case object
      when Array
        object.sort.each do |item|
          hputs("#{item}")
        end
        hputs
      when Hash
        key_length = object.keys.map {|key| key.length}.max + 2
        sorted_keys = object.keys.sort_by {|key| key.to_s}
        sorted_keys.each do |key|
          hprint("#{key}: ".ljust(key_length))
          case data = object[key]
          when Array
            data.sort.each_with_index do |item, index|
              unless index == 0
                hprint(" " * key_length)
              end
              hputs(item)
            end
            hputs
          else
            hputs("#{data}")
          end
        end
        unless object[sorted_keys.last].is_a?(Array)
          hputs
        end
      else
        hputs(object.to_s)
      end
    end

  end
end
