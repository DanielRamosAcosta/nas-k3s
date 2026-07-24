local mcRouter = import 'games/mc-router/mc-router.libsonnet';
local minecraftBackup = import 'games/minecraft-backup/minecraft-backup.libsonnet';
local minecraft = import 'games/minecraft/minecraft.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  minecraft: minecraft.new(),
  mcRouter: mcRouter.new(),
  minecraftBackup: minecraftBackup.new(),
})
