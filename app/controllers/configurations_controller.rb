class ConfigurationsController < ApplicationController
  MODAL_PATTERNS = [
    "/new$",
    "/new\\?.*",
    "/edit$",
    "/edit\\?.*",
    "/sign_in",
    "/sign_up",
    "/login",
    "/signup",
    "/users/sign_in",
    "/users/sign_up",
    "/users/password/new",
    "/users/password/edit",
    "/community/new"
  ].freeze

  def ios_v1
    render json: {
      settings: {},
      rules: [
        {
          patterns: [ ".*" ],
          properties: {
            context: "default",
            pull_to_refresh_enabled: true
          }
        },
        {
          patterns: [ "/mobile_auth/redeem" ],
          properties: {
            context: "default",
            presentation: "replace_root",
            pull_to_refresh_enabled: false
          }
        },
        {
          patterns: MODAL_PATTERNS,
          properties: {
            context: "modal",
            pull_to_refresh_enabled: false
          }
        }
      ]
    }
  end

  def android_v1
    render json: {
      settings: {},
      rules: [
        {
          patterns: [ ".*" ],
          properties: {
            context: "default",
            uri: "hotwire://fragment/web",
            pull_to_refresh_enabled: true
          }
        },
        {
          patterns: [ "/mobile_auth/redeem" ],
          properties: {
            context: "default",
            uri: "hotwire://fragment/web",
            presentation: "replace_root",
            pull_to_refresh_enabled: false
          }
        },
        {
          patterns: MODAL_PATTERNS,
          properties: {
            context: "modal",
            uri: "hotwire://fragment/web/modal/sheet",
            pull_to_refresh_enabled: false
          }
        }
      ]
    }
  end
end
