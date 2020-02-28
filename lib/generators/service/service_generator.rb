class ServiceGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  argument :methods, type: :array, default: [], banner: "method method"
	class_option :module, type: :string

	def create_service_file
		@module_name = options[:module]

		services_dir = "app/services"
		new_service_dir = services_dir + ("/#{@module_name.underscore}" if @module_name.present?).to_s
		service_file = new_service_dir + "/#{file_name}.rb"

		Dir.mkdir(services_dir) unless File.exist?(services_dir)
		Dir.mkdir(new_service_dir) unless File.exist?(new_service_dir)

		tests_dir = "test/services"
		new_test_dir = tests_dir + ("/#{@module_name.underscore}" if @module_name.present?).to_s
		test_file = new_test_dir + "/#{file_name}_test.rb"

		Dir.mkdir(tests_dir) unless File.exist?(tests_dir)
		Dir.mkdir(new_test_dir) unless File.exist?(new_test_dir)

		template "service.erb", service_file
		template "service_test.erb", test_file
	end
end
