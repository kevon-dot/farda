# board_config: header-only hardware abstraction (INTERFACE component).
idf_component_register(
    INCLUDE_DIRS "include"
    REQUIRES driver
)
