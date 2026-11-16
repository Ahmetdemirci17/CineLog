module ApplicationHelper
  # Wraps in-page filter/tab sections in a Turbo Frame so filter changes update in place.
  # On web browsers `turbo_action: "advance"` syncs the URL; inside Hotwire Native apps
  # omitting it prevents Frame updates from proposing a full native visit/screen push.
  def filter_frame_tag(id, **options, &block)
    data = (options.delete(:data) || {}).dup
    data[:turbo_action] = "advance" unless hotwire_native_app? || data.key?(:turbo_action)
    css_class = [ "block", options.delete(:class) ].compact_blank.join(" ")
    turbo_frame_tag(id, target: "_top", class: css_class, data: data, **options, &block)
  end
end
