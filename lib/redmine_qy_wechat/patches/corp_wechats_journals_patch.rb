module CorpWechatsJournalsPatch
  extend ActiveSupport::Concern
  # 当创建journal时发送消息
  require 'net/http'
  require 'net/https'

  included do
    after_create :send_messages_after_create_journal
  end
  
  # 用企业微信发送 
  def send_by_wechat(send_people_wx)
       #填写确认并应用的企业ID
      corpid = Setting["plugin_redmine_work_wechat"]["wechat_corp_id"]
      #填写确认并应用的应用Secret
      corpsecret = Setting["plugin_redmine_work_wechat"]["wechat_app_secret"]
      
      app_id = Setting["plugin_redmine_work_wechat"]["wechat_app_id"]
            
      if corpid.blank? || corpsecret.blank? || app_id.blank?
        return
      end
      @group_client = QyWechatApi::Client.new(corpid, corpsecret)
      # 为了确保用户输入的corpid, corpsecret是准确的，请务必执行：
        
      if @group_client.blank?
        return
      end
  
      
      # 改成异常捕捉，避免is_valid?方法本身的出错
      begin
        if @group_client.is_valid?
        #options = {access_token: "access_token"}
        # redis_key 也可定制
        #group_client = QyWechatApi::Client.new(corpid, corpsecret, options)
        #issue
        #填写确认并应用的应用AgentId
  
          @group_client.message.send_text(send_people_wx, "", "", app_id,
          "#{l(:msg_focus)} <a href=\'" + Setting.protocol + "://" + Setting.host_name + "/issues/#{@issue.id}\'>#{@issue.tracker} ##{@issue.id}: #{@issue.subject}</a> #{l(:msg_by)} <a href=\'javascript:void(0);\'>#{@issue.journals.last.user}</a> #{l(:msg_updated)}")
        end
      rescue
      end
  end
      
  # 用钉钉发送 
  def send_by_dingtalk(send_people_dd)
    #填写确认并应用的企业ID
    corpid = Setting["plugin_redmine_work_wechat"]["dingtalk_corp_id"]
    #填写确认并应用的应用ID（AgentID）
    appid = Setting["plugin_redmine_work_wechat"]["dingtalk_app_id"]
    #填写确认并应用的应用key
    appkey = Setting["plugin_redmine_work_wechat"]["dingtalk_app_key"]
    #填写确认并应用的应用Secret
    appsecret = Setting["plugin_redmine_work_wechat"]["dingtalk_app_secret"]
            
    logger.info(corpid)
    logger.info(appkey)
    logger.info(appsecret)
    logger.info(appid)
    if corpid.blank? || appkey.blank? || appsecret.blank? || appid.blank?
      return
    end
    # uri = URI.parse("https://oapi.dingtalk.com/gettoken?corpid=#{corpid}&corpsecret=#{corpsecret}")
    uri = URI.parse("https://oapi.dingtalk.com/gettoken?appkey=#{appkey}&appsecret=#{appsecret}")
    # 改成异常捕捉，避免is_valid?方法本身的出错
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
            
      response = http.request(request)
          
      # 获得token
      token = JSON.parse(response.body)["access_token"]
      logger.info(JSON.parse(response.body)["errcode"])
      logger.info(JSON.parse(response.body)["errmsg"])
      logger.info("token:#{token}")
    
      # issue_url = issue_url(@issue)
      issue_url =  Setting.protocol + "://" + Setting.host_name + "/issues/#{@issue.id}"
      # issue_title = @issue.project.name
      issue_title = "#{@issue.project.name} - (#{@issue.tracker} ##{@issue.id})#{@issue.subject}"

      # issue_text = "#{@issue.tracker} ##{@issue.id}: #{@issue.subject} #{@issue.status} #{@issue.done_ratio}% #{l(:msg_by)} #{@issue.author} #{l(:msg_created)}"
      # issue_text = "#{@issue.tracker} ##{@issue.id}:  #{@issue.notes} #{@issue.done_ratio}% #{l(:msg_by)} #{@issue.author} #{l(:msg_updated)}"
      issue_text = "#{l(:msg_by)} #{@issue.journals.last.user} #{l(:msg_updated)}(##{@issue.journals.size}) #{@issue.done_ratio}% \n----------\n#{@issue.notes}"

      data = {
        msg: {
          msgtype: "link",
          link: {
              messageUrl: issue_url,
	      picUrl: "http://web.xnpool.cn/redmine/images/xnLogo.jpeg",
              title: issue_title,
              text: issue_text
          }
        }
      }.to_json
        
      logger.info("start request")
      logger.info(data)
      url = URI.parse("https://oapi.dingtalk.com/topapi/message/corpconversation/asyncsend_v2?access_token=#{token}&agent_id=#{appid}&userid_list=#{send_people_dd}") 
      # url = URI.parse("https://oapi.dingtalk.com/chat/send?access_token=#{token}")  
      # url = URI.parse("https://oapi.dingtalk.com/chat/send?access_token=#{token}&chatid=chatd58978ab82b4e2598b4c5540a1241d41")  
      http = Net::HTTP.new(url.host,url.port)
      http.use_ssl = true
      
      logger.info("url.request_uri")
      logger.info(url.request_uri)
      #req = Net::HTTP::Post.new(url.path, initheader = {'Content-Type' =>'application/json'})
      req = Net::HTTP::Post.new(url.request_uri, 'Content-Type' => 'application/json')
      
      req.body = data
      # req.body = dingtalk_account_number
      res = http.request(req)
      logger.info("response")
      logger.info(JSON.parse(response.body)["errcode"])
      logger.info(JSON.parse(response.body)["errmsg"])
      logger.info(JSON.parse(response.body)["task_id"])
    rescue =>e
      logger.info(e)
    end
  end

  def send_messages_after_create_journal
    # firstly ignore the anonymouse to avoid notification bug
    # 拷贝app_notifications_journals_patch.rb
    if user.id == 2
      return
    end
    issue = journalized.reload
    to_users = notified_users
    cc_users = notified_watchers - to_users
    notify_users = to_users + cc_users
    
    
    issue = journalized
    @issue = issue
    
    if notify?
      # 需要接受微信和钉钉的用户ID集合
      send_people_wx = ""
      send_people_dd = ""
      # 用@issue自带的方法获取需要通知的用户列表
            
      notify_users.each do |user|
        unless user.corp_wechat_account_number.blank?
          send_people_wx.concat(user.corp_wechat_account_number).concat("|")
        end
        unless user.dingtalk_account_number.blank?
          send_people_dd.concat(user.dingtalk_account_number).concat(",")
        end
      end
      

      # # 作者
      # unless @issue.author_id.nil?
      #   unless User.where(:id => @issue.author_id).first.corp_wechat_account_number.blank?
      #     send_people_wx.concat(User.where(:id => @issue.author_id).first.corp_wechat_account_number).concat("|")
      #   end
      # end
      
      # # 指派者
      # unless @issue.assigned_to_id.nil?
      #   unless User.where(:id => @issue.assigned_to_id).first.corp_wechat_account_number.blank?
      #     send_people_wx.concat(User.where(:id => @issue.assigned_to_id).first.corp_wechat_account_number).concat("|")
      #   end
      # end

      # # 关注者
      # @issue.watcher_users.each do |information|
      #   unless User.where(:id => information.id).first.corp_wechat_account_number.blank?
      #     send_people_wx.concat(User.where(:id => information.id).first.corp_wechat_account_number).concat("|")
      #   end
      # end
      
      if !send_people_wx.blank?
        send_by_wechat send_people_wx
      end
      
      # 以下是钉钉的处理
      # 作者
      # unless @issue.author_id.nil?
      #   unless User.where(:id => @issue.author_id).first.dingtalk_account_number.blank?
      #     send_people_dd.concat(User.where(:id => @issue.author_id).first.dingtalk_account_number).concat("|")
      #   end
      # end
      
      # # 指派者
      # unless @issue.assigned_to_id.nil?
      #   unless User.where(:id => @issue.assigned_to_id).first.dingtalk_account_number.blank?
      #     send_people_dd.concat(User.where(:id => @issue.assigned_to_id).first.dingtalk_account_number).concat("|")
      #   end
      # end

      # # 关注者
      # @issue.watcher_users.each do |information|
      #   unless User.where(:id => information.id).first.dingtalk_account_number.blank?
      #     send_people_dd.concat(User.where(:id => information.id).first.dingtalk_account_number).concat("|")
      #   end
      # end
      
      if !send_people_dd.blank?
        send_by_dingtalk send_people_dd
      end
    end
  end
end

Journal.send(:include, CorpWechatsJournalsPatch)
