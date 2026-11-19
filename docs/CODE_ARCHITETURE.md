workspace-overview/
├── plugin.toml
├── panel.luau      # Entrypoint (connects the MVVM and expose onOpen / onIpc)
├── model.luau      # Model (types, JSON, compositor calls)
├── viewmodel.luau  # ViewModel (UI state and user commands)
└── view.luau       # View (UI declarative components)