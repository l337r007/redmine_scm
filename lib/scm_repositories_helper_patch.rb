require_dependency 'repositories_helper'

module ScmRepositoriesHelperPatch

    def self.included(base)
        base.extend(ClassMethods)
        base.send(:include, InstanceMethods)
        base.class_eval do
            unloadable
            alias_method_chain :repository_field_tags, :add
            alias_method_chain :subversion_field_tags, :add
            alias_method_chain :mercurial_field_tags,  :add
            alias_method_chain :git_field_tags,        :add
            alias_method_chain :bazaar_field_tags,     :add

            # extra methods not method_chained somehow(?) need to go here.

            def scm_creator_max_repositories_reached()
                return @project.respond_to?(:repositories) &&
                       ScmConfig['max_repos'] &&
                       ScmConfig['max_repos'].to_i > 0 &&
                       @project.repositories.select{ |r| r.created_with_scm }.size >= ScmConfig['max_repos'].to_i
            end

            def scm_creator_create_button()
                if defined? observe_field # Rails 3.0 and below
                    return submit_tag(l(:button_create_new_repository), :onclick => "$('repository_operation').value = 'add';")
                else # Rails 3.1 and above
                    return submit_tag(l(:button_create_new_repository), :onclick => "$('#repository_operation').val('add');")
                end
            end

            def scm_creator_add_tag_to_set_repository_url_to(tags, path)
                if defined? observe_field # Rails 3.0 and below
                    tags << javascript_tag("$('repository_url').value = '#{escape_javascript(path)}';")
                else # Rails 3.1 and above
                    tags << javascript_tag("$('#repository_url').val('#{escape_javascript(path)}');")
                end
            end

            def scm_creator_suggest_name(creator_interface)
                name = @project.identifier.dup
                if creator_interface.repository_exists?(@project.identifier) && @project.respond_to?(:repositories)
                    name << '.' + @project.repositories.select{ |r| r.created_with_scm }.size.to_s
                end
                return name
            end

            def scm_creator_suggest_path(creator_interface)
                suggested_reponame = scm_creator_suggest_name(creator_interface)
                repopath = creator_interface.default_path(suggested_reponame)
                return creator_interface.access_root_url(repopath)
            end

        end
    end

    module ClassMethods
    end

    module InstanceMethods

        def repository_field_tags_with_add(form, repository)
            reptags = repository_field_tags_without_add(form, repository)

            button_disabled = repository.class.respond_to?(:scm_available) ? !repository.class.scm_available : false

            if ScmConfig['only_creator']
                begin
                    interface = Object.const_get("#{repository.class.name.demodulize}Creator")
                rescue NameError
                end

                if interface && (interface < SCMCreator) && interface.enabled? && repository.new_record?
                    button_disabled = true
                end
            end

            if defined? observe_field # Rails 3.0 and below
                if request.xhr?
                    reptags << javascript_tag("$('repository_save')." + (button_disabled ? 'disable' : 'enable') + "();")
                else
                    reptags << javascript_tag("Event.observe(window, 'load', function() { $('repository_save')." + (button_disabled ? 'disable' : 'enable') + "(); });")
                end
            else # Rails 3.1 and above
                if request.xhr?
                    reptags << javascript_tag("$('#repository_save')." + (button_disabled ? "attr('disabled','disabled')" : "removeAttr('enable')") + ";")
                else
                    reptags << javascript_tag("$(document).ready(function() { $('#repository_save')." + (button_disabled ? "attr('disabled','disabled')" : "removeAttr('enable')") + "; });")
                end
            end

            return reptags.html_safe
        end

        def subversion_field_tags_with_add(form, repository)
            svntags = subversion_field_tags_without_add(form, repository)
            svntags.gsub!('&lt;br /&gt;', '<br />')

            return svntags if scm_creator_max_repositories_reached()
            return svntags unless SubversionCreator.enabled?

            if repository.new_record?
                svntags.gsub!('<br />', ' ' + scm_creator_create_button() + '<br />')
                svntags << hidden_field_tag(:operation, '', :id => 'repository_operation')
                unless request.post?
                    path = scm_creator_suggest_path(SubversionCreator)
                    scm_creator_add_tag_to_set_repository_url_to(svntags, path)
                end

            elsif !repository.new_record? && repository.created_with_scm &&
                SubversionCreator.enabled? && SubversionCreator.options['url'].present?
                name = SubversionCreator.repository_name(repository.root_url)
                if name
                    svntags.gsub!('(file:///, http://, https://, svn://, svn+[tunnelscheme]://)', SubversionCreator.external_url(name))
                end
            end

            return svntags
        end

        def mercurial_field_tags_with_add(form, repository)
            hgtags = mercurial_field_tags_without_add(form, repository)

            return hgtags if scm_creator_max_repositories_reached()
            return hgtags unless MercurialCreator.enabled?

            if repository.new_record?
                if hgtags.include?('<br />')
                    hgtags.gsub!('<br />', ' ' + scm_creator_create_button() + '<br />')
                else
                    hgtags.gsub!('</p>', ' ' + scm_creator_create_button() + '</p>')
                end
                hgtags << hidden_field_tag(:operation, '', :id => 'repository_operation')
                unless request.post?
                    path = scm_creator_suggest_path(MercurialCreator)
                    scm_creator_add_tag_to_set_repository_url_to(hgtags, path)
                end

            elsif !repository.new_record? && repository.created_with_scm &&
                MercurialCreator.enabled? && MercurialCreator.options['url'].present?
                name = MercurialCreator.repository_name(repository.root_url)
                if name
                    if hgtags.include?(l(:text_mercurial_repository_note))
                        hgtags.gsub!(l(:text_mercurial_repository_note), MercurialCreator.external_url(name))
                    elsif hgtags.include?(l(:text_mercurial_repo_example))
                        hgtags.gsub!(l(:text_mercurial_repo_example), MercurialCreator.external_url(name))
                    else
                        hgtags.gsub!('</p>', '<br />' + MercurialCreator.external_url(name) + '</p>')
                    end
                end
            end

            return hgtags
        end

        def bazaar_field_tags_with_add(form, repository)
            bzrtags = bazaar_field_tags_without_add(form, repository)

            return bzrtags if scm_creator_max_repositories_reached()
            return bzrtags unless BazaarCreator.enabled?

            if repository.new_record?
                bzrtags.gsub!('</p>', ' ' + scm_creator_create_button() + '</p>')
                bzrtags << hidden_field_tag(:operation, '', :id => 'repository_operation')
                unless request.post?
                    path = scm_creator_suggest_path(BazaarCreator)
                    scm_creator_add_tag_to_set_repository_url_to(bzrtags, path)
                    if BazaarCreator.options['log_encoding']
                        if defined? observe_field # Rails 3.0 and below
                            bzrtags << javascript_tag("$('repository_log_encoding').value = '#{escape_javascript(BazaarCreator.options['log_encoding'])}';")
                        else # Rails 3.1 and above
                            bzrtags << javascript_tag("$('#repository_log_encoding').val('#{escape_javascript(BazaarCreator.options['log_encoding'])}');")
                        end
                    end
                end

            elsif !repository.new_record? && repository.created_with_scm &&
                BazaarCreator.enabled? && BazaarCreator.options['url'].present?
                name = BazaarCreator.repository_name(repository.root_url)
                if name
                    bzrtags.gsub!('</p>', '<br />' + BazaarCreator.external_url(name) + '</p>')
                end
            end

            return bzrtags
        end

        def git_field_tags_with_add(form, repository)
            gittags = git_field_tags_without_add(form, repository)

            return gittags if scm_creator_max_repositories_reached()
            return gittags unless GitCreator.enabled?

            if repository.new_record?
                if gittags.include?('<br />')
                    gittags.gsub!('<br />', ' ' + scm_creator_create_button() + '<br />')
                else
                    gittags.gsub!('</p>', ' ' + scm_creator_create_button() + '</p>')
                end
                gittags << hidden_field_tag(:operation, '', :id => 'repository_operation')
                unless request.post?
                    path = scm_creator_suggest_path(GitCreator)
                    scm_creator_add_tag_to_set_repository_url_to(gittags, path)
                end

            elsif !repository.new_record? && repository.created_with_scm &&
                GitCreator.enabled? && GitCreator.options['url'].present?
                name = GitCreator.repository_name(repository.root_url)
                if name
                    if gittags.include?(l(:text_git_repository_note))
                        gittags.gsub!(l(:text_git_repository_note), GitCreator.external_url(name))
                    elsif gittags.include?(l(:text_git_repo_example))
                        gittags.gsub!(l(:text_git_repo_example), GitCreator.external_url(name))
                    else
                        gittags.gsub!('</p>', '<br />' + GitCreator.external_url(name) + '</p>')
                    end
                end
            end

            return gittags
        end

    end

end
