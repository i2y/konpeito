# Castella UI - Tree Widget Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as tree_demo.rb but uses NativeFrame instead of JWMFrame.
# Demonstrates: Tree view with expand/collapse, selection, scrolling
# Run: ruby examples/castella_ui/native_tree_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

$theme = Theme.new

def build_sample_tree
  root = TreeNode.new("project", "my-project")
  src = TreeNode.new("src", "src")
  src.add_child(TreeNode.new("main", "main.rb"))
  src.add_child(TreeNode.new("utils", "utils.rb"))
  src.add_child(TreeNode.new("config", "config.rb"))
  models = TreeNode.new("models", "models")
  models.add_child(TreeNode.new("user", "user.rb"))
  models.add_child(TreeNode.new("post", "post.rb"))
  models.add_child(TreeNode.new("comment", "comment.rb"))
  src.add_child(models)
  views = TreeNode.new("views", "views")
  views.add_child(TreeNode.new("home", "home.erb"))
  views.add_child(TreeNode.new("about", "about.erb"))
  layouts = TreeNode.new("layouts", "layouts")
  layouts.add_child(TreeNode.new("app_layout", "application.erb"))
  views.add_child(layouts)
  src.add_child(views)
  root.add_child(src)
  test_dir = TreeNode.new("test", "test")
  test_dir.add_child(TreeNode.new("test_main", "test_main.rb"))
  test_dir.add_child(TreeNode.new("test_utils", "test_utils.rb"))
  fixtures = TreeNode.new("fixtures", "fixtures")
  fixtures.add_child(TreeNode.new("users_yml", "users.yml"))
  fixtures.add_child(TreeNode.new("posts_yml", "posts.yml"))
  test_dir.add_child(fixtures)
  root.add_child(test_dir)
  root.add_child(TreeNode.new("gemfile", "Gemfile"))
  root.add_child(TreeNode.new("readme", "README.md"))
  root.add_child(TreeNode.new("rakefile", "Rakefile"))
  [root]
end

class TreeDemo < Component
  def initialize
    super()
    nodes = build_sample_tree
    @tree_state = TreeState.new(nodes)
    @tree_state.expand("project")
    @tree_state.expand("src")
    @sel_label = State.new("None")
    @tree_state.attach(self)
  end

  def on_attach(observable)
  end

  def on_detach(observable)
  end

  def on_notify
    sid = @tree_state.selected_id
    label = "" + sid
    @sel_label.set(label)
    @pending_rebuild = true
    mark_paint_dirty
    a = App.current
    if a != nil
      a.post_update(self)
    end
  end

  def view
    ts = @tree_state
    sel_text = @sel_label.value
    Column(
      Text("Tree Widget Demo").font_size(22.0).color(0xFFC0CAF5).bold,
      Divider(),
      Row(
        Text("Selected: ").font_size(13.0),
        Text(sel_text).font_size(13.0).color(0xFF7AA2F7)
      ).spacing(4.0).fixed_height(24.0),
      Row(
        Button("Expand All").on_click { ts.expand_all },
        Button("Collapse All").on_click { ts.collapse_all }
      ).spacing(8.0).fixed_height(36.0),
      Divider(),
      Tree(ts)
    ).spacing(8.0)
  end
end

frame = NativeFrame.new("Tree Demo", 600, 600)
app = App.new(frame, TreeDemo.new)
app.run
