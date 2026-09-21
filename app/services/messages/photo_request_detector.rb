module Messages
  class PhotoRequestDetector
    PHOTO_WORD = /(?:фото(?:графи[юя]|чк[уи])?|фотк[уиа]?|селфи|снимок|pic(?:ture)?|photo|selfie)/i
    REQUEST_WORD = /(?:пришл\w*|отправ\w*|покаж\w*|скин\w*|сдела\w*|send|show|take|make)/i
    MAX_DISTANCE = 80

    def self.call(content)
      text = content.to_s
      photo_match = PHOTO_WORD.match(text)
      request_match = REQUEST_WORD.match(text)
      return false unless photo_match && request_match

      (photo_match.begin(0) - request_match.begin(0)).abs <= MAX_DISTANCE
    end
  end
end
