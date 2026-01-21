#!/usr/bin/env -S deno run --allow-all

// Purge script to clean up Lima VMs

// Set LIMA_HOME to VM directory for all persistence concerns
const LIMA_HOME = "/Volumes/MacOS/Lima/VM";
Deno.env.set("LIMA_HOME", LIMA_HOME);

async function runCommand(cmd: string[]): Promise<{ success: boolean; output: string }> {
    try {
        const process = new Deno.Command(cmd[0], {
            args: cmd.slice(1),
            stdout: "piped",
            stderr: "piped",
        });
        
        const { code, stdout, stderr } = await process.output();
        const output = new TextDecoder().decode(stdout) + new TextDecoder().decode(stderr);
        
        return { success: code === 0, output };
    } catch (error) {
        return { success: false, output: error.toString() };
    }
}

async function main() {
    console.log(`Purging Lima VMs from: ${LIMA_HOME}`);
    
    // Get list of VMs
    const listResult = await runCommand(["limactl", "list", "--format", "{{.Name}}"]);
    
    if (listResult.success) {
        const vms = listResult.output.trim().split('\n').filter(vm => vm.length > 0);
        
        if (vms.length > 0) {
            console.log(`Found ${vms.length} VM(s) to purge:`);
            
            // Stop all VMs
            for (const vm of vms) {
                console.log(`Stopping VM: ${vm}`);
                await runCommand(["limactl", "stop", vm]);
            }
            
            // Delete all VMs
            for (const vm of vms) {
                console.log(`Deleting VM: ${vm}`);
                const deleteResult = await runCommand(["limactl", "delete", "--force", vm]);
                if (!deleteResult.success) {
                    console.error(`Failed to delete VM ${vm}: ${deleteResult.output}`);
                }
            }
        } else {
            console.log("No VMs found to purge.");
        }
    } else {
        console.log("Unable to list VMs.");
    }
    
    // Clean up Lima home directory
    if (await Deno.stat(LIMA_HOME).catch(() => null)) {
        console.log(`\nCleaning up Lima home directory: ${LIMA_HOME}`);
        await Deno.remove(LIMA_HOME, { recursive: true });
        console.log("Lima home directory removed.");
    }
    
    console.log("\nPurge complete!");
}

await main();
