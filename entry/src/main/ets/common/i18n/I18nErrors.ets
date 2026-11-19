/** 词条分域：Errors（由 scripts/i18n_split.mjs 生成，勿手改本文件结构） */
export const ZH_ERRORS: Record<string, string> = {
  'commonNetworkErrorToast': '网络异常，请检查你的网络状况',
  'replyInvalidApiKey': 'API Key 无效或已被删除，请更换后重试',
  'replyInsufficientBalance': '账户余额不足，请充值后重试',
  'replyRateLimited': '请求过于频繁，请稍后再试',
  'completionServerBusyToast': '服务器繁忙，请稍后再试',
  'unknownError': '未知错误',
  'requestFailed': '请求失败：{message}',
};

export const EN_ERRORS: Record<string, string> = {
  'commonNetworkErrorToast': 'Network error. Please check your connection.',
  'replyInvalidApiKey': 'API Key is invalid or deleted. Please change it and retry.',
  'replyInsufficientBalance': 'Insufficient balance. Please top up and retry.',
  'replyRateLimited': 'Too many requests. Please retry later.',
  'completionServerBusyToast': 'Server busy. Please retry later.',
  'unknownError': 'Unknown error',
  'requestFailed': 'Request failed: {message}',
};
