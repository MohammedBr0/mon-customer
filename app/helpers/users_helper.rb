# frozen_string_literal: true

module UsersHelper
  DEFAULT_USER_PROFILE_SIZE = 40

  def user_profile_picture_url(user, _type = :square)
    if user_signed_in? && user.image?
      user.image
    else
      asset_pack_path('static/images/user.jpg')
    end
  end

  def user_profile_picture(user, size: DEFAULT_USER_PROFILE_SIZE, type: :square, options: {})
    tag.img(width:  size,
            height: size,
            src:    user_profile_picture_url(user, type),
            alt:    '',
            class:  'img-fluid', **options)
  end
end
